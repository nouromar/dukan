-- 0104_ocr_worker.sql
--
-- Bono OCR, slice 3 (backend worker contract). The two RPCs the ocr-bono edge
-- function calls, plus the lease_token that makes claim/complete exactly-once.
--
-- Concurrency model (why lease_token exists):
--   * A bono insert enqueues a 'queued' job and kicks the edge fn (fast path).
--   * The pg_cron poller independently claims + kicks (backbone).
-- Both the poller's batch claim and _ocr_begin_job flip 'queued'->'processing'
-- with a COMPARE-AND-SET on status='queued', so exactly ONE of them claims a
-- given job — the loser sees it's no longer queued and does nothing. The
-- claimer stamps a fresh lease_token; the edge fn echoes that token back to
-- _ocr_complete_job, which only writes if the token still matches. So if a job
-- times out, gets reclaimed by the poller, and is re-leased to a new worker,
-- the original (slow) worker's late completion is a no-op — no clobber, no
-- double result.

-- 1. The lease token. Nullable: a queued/idle job holds none.
alter table public.ocr_job add column if not exists lease_token uuid;

-- ---------------------------------------------------------------------------
-- 2. _ocr_dispatch_kick gains the lease token so the poller can hand the edge
--    fn a job it already claimed (the edge fn skips its own claim when a token
--    is present). Drop the 1-arg form; the 2-arg default keeps existing
--    callers (trigger) resolving to token=null.
-- ---------------------------------------------------------------------------
drop function if exists public._ocr_dispatch_kick(uuid);

create or replace function public._ocr_dispatch_kick(p_job_id uuid, p_lease_token uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url   text := public._ocr_config(null, 'ocr_edge_url', 'null'::jsonb) #>> '{}';
  v_token text := public._ocr_config(null, 'ocr_dispatch_token', 'null'::jsonb) #>> '{}';
begin
  if v_url is null or pg_catalog.length(pg_catalog.btrim(v_url)) = 0 then
    return;
  end if;
  if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_net') then
    perform net.http_post(
      url     := v_url,
      headers := pg_catalog.jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || coalesce(v_token, '')),
      body    := pg_catalog.jsonb_build_object('job_id', p_job_id, 'lease_token', p_lease_token)
    );
  end if;
exception when others then
  return;  -- the poller backstops every job; a kick failure is a non-event
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. _drain_ocr_jobs: same as 0103 but the batch claim now stamps a lease_token
--    and hands it to the kick, so a poller-claimed job carries its lease to the
--    edge fn.
-- ---------------------------------------------------------------------------
create or replace function public._drain_ocr_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lease    integer := coalesce((public._ocr_config(null, 'ocr_job_lease_seconds',     '60'::jsonb) #>> '{}')::integer, 60);
  v_batch    integer := coalesce((public._ocr_config(null, 'ocr_poller_batch_size',     '25'::jsonb) #>> '{}')::integer, 25);
  v_global   integer := coalesce((public._ocr_config(null, 'ocr_max_concurrent_global', '50'::jsonb) #>> '{}')::integer, 50);
  v_per_shop integer := coalesce((public._ocr_config(null, 'ocr_max_per_shop_per_min',  '10'::jsonb) #>> '{}')::integer, 10);
  v_max_att  integer := coalesce((public._ocr_config(null, 'ocr_max_attempts',          '3'::jsonb)  #>> '{}')::integer, 3);
  v_inflight integer;
  v_budget   integer;
  v_claimed  integer := 0;
  r          record;
begin
  update public.ocr_job
     set status = 'queued', locked_at = null, lease_token = null, updated_at = pg_catalog.now()
   where status = 'processing'
     and locked_at is not null
     and locked_at < pg_catalog.now() - pg_catalog.make_interval(secs => v_lease);

  update public.ocr_job
     set status = 'failed', locked_at = null, updated_at = pg_catalog.now(),
         last_error = coalesce(last_error, 'max attempts exceeded')
   where status = 'queued' and attempts >= v_max_att;

  select pg_catalog.count(*) into v_inflight from public.ocr_job where status = 'processing';
  v_budget := least(v_batch, greatest(v_global - v_inflight, 0));
  if v_budget <= 0 then
    return 0;
  end if;

  for r in
    with candidate as (
      select q.id, q.shop_id,
             pg_catalog.row_number() over (partition by q.shop_id order by q.created_at, q.id) as shop_rank,
             (select pg_catalog.count(*) from public.ocr_job p
               where p.shop_id = q.shop_id and p.status = 'processing') as shop_inflight
      from public.ocr_job q
      where q.status = 'queued' and q.attempts < v_max_att
    ),
    eligible as (
      select id from candidate
      where shop_rank + shop_inflight <= v_per_shop
      order by id
      limit v_budget
    )
    update public.ocr_job j
       set status = 'processing', locked_at = pg_catalog.now(),
           attempts = j.attempts + 1, lease_token = pg_catalog.gen_random_uuid(),
           updated_at = pg_catalog.now()
     where j.id in (select id from eligible)
       and j.status = 'queued'
    returning j.id, j.lease_token
  loop
    v_claimed := v_claimed + 1;
    perform public._ocr_dispatch_kick(r.id, r.lease_token);
  end loop;

  return v_claimed;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. _ocr_begin_job — the edge fn's fast-path claim (kick without a token).
--    Cap-aware compare-and-set on status='queued'; returns the signed-URL
--    inputs + the fresh lease token, or nothing (not queued / over budget).
-- ---------------------------------------------------------------------------
create or replace function public._ocr_begin_job(p_job_id uuid)
returns table (
  document_id     uuid,
  shop_id         uuid,
  storage_bucket  text,
  storage_path    text,
  mime_type       text,
  organization_id uuid,
  lease_token     uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_global   integer := coalesce((public._ocr_config(null, 'ocr_max_concurrent_global', '50'::jsonb) #>> '{}')::integer, 50);
  v_per_shop integer := coalesce((public._ocr_config(null, 'ocr_max_per_shop_per_min',  '10'::jsonb) #>> '{}')::integer, 10);
  v_max_att  integer := coalesce((public._ocr_config(null, 'ocr_max_attempts',          '3'::jsonb)  #>> '{}')::integer, 3);
  v_token    uuid := pg_catalog.gen_random_uuid();
  v_doc      uuid;
  v_shop     uuid;
begin
  update public.ocr_job j
     set status = 'processing', locked_at = pg_catalog.now(),
         attempts = j.attempts + 1, lease_token = v_token, updated_at = pg_catalog.now()
   where j.id = p_job_id
     and j.status = 'queued'
     and j.attempts < v_max_att
     and (select pg_catalog.count(*) from public.ocr_job p where p.status = 'processing') < v_global
     and (select pg_catalog.count(*) from public.ocr_job p where p.shop_id = j.shop_id and p.status = 'processing') < v_per_shop
   returning j.document_id, j.shop_id into v_doc, v_shop;

  if v_doc is null then
    return;  -- not queued, exhausted, or over budget
  end if;

  update public.document
     set ocr_status_id = (select id from public.ocr_status where code = 'processing'),
         updated_at = pg_catalog.now()
   where document.shop_id = v_shop and document.id = v_doc;

  return query
    select d.id, d.shop_id, d.storage_bucket, d.storage_path, d.mime_type, s.organization_id, v_token
    from public.document d
    join public.shop s on s.id = d.shop_id
    where d.shop_id = v_shop and d.id = v_doc;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. _ocr_complete_job — the edge fn writes the AI result (or a failure) back,
--    guarded by the lease token. success -> write ocr_result; a retryable
--    failure under the attempt cap -> requeue; else -> dead-letter.
--    Returns true iff this worker still held the lease (i.e. the write applied).
-- ---------------------------------------------------------------------------
create or replace function public._ocr_complete_job(
  p_job_id      uuid,
  p_lease_token uuid,
  p_status      text,
  p_result      jsonb   default null,
  p_error       text    default null,
  p_retryable   boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_att integer := coalesce((public._ocr_config(null, 'ocr_max_attempts', '3'::jsonb) #>> '{}')::integer, 3);
  v_shop uuid;
  v_doc  uuid;
  v_att  integer;
  v_new  text;
begin
  if p_status not in ('success', 'failed') then
    raise exception 'invalid ocr completion status: %', p_status;
  end if;

  -- Lease check + row lock. A stale worker (token no longer current) gets nothing.
  select j.shop_id, j.document_id, j.attempts into v_shop, v_doc, v_att
  from public.ocr_job j
  where j.id = p_job_id and j.lease_token = p_lease_token and j.status = 'processing'
  for update;
  if v_shop is null then
    return false;
  end if;

  if p_status = 'success' then
    v_new := 'success';
  elsif p_retryable and v_att < v_max_att then
    v_new := 'queued';   -- transient error; the poller re-kicks it
  else
    v_new := 'failed';
  end if;

  update public.ocr_job
     set status      = v_new,
         last_error  = p_error,
         lease_token = case when v_new = 'queued' then null else lease_token end,
         locked_at   = case when v_new = 'queued' then null else locked_at end,
         updated_at  = pg_catalog.now()
   where id = p_job_id;

  if p_status = 'success' then
    update public.document
       set ocr_result   = coalesce(p_result, ocr_result),
           ocr_status_id = (select id from public.ocr_status where code = 'success'),
           updated_at   = pg_catalog.now()
     where document.shop_id = v_shop and document.id = v_doc;
  elsif v_new = 'failed' then
    update public.document
       set ocr_status_id = (select id from public.ocr_status where code = 'failed'),
           updated_at   = pg_catalog.now()
     where document.shop_id = v_shop and document.id = v_doc;
  end if;

  return true;
end;
$$;

-- The worker RPCs are called by the edge function under the service role only.
revoke all on function public._ocr_begin_job(uuid) from public;
revoke all on function public._ocr_complete_job(uuid, uuid, text, jsonb, text, boolean) from public;
grant execute on function public._ocr_begin_job(uuid) to service_role;
grant execute on function public._ocr_complete_job(uuid, uuid, text, jsonb, text, boolean) to service_role;
