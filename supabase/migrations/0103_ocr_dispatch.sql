-- 0103_ocr_dispatch.sql
--
-- Bono OCR, slice 2 (dispatch). Turns a freshly-inserted bono `document` into a
-- claimed, leased `ocr_job` that the edge worker (slice 3) processes. Two paths,
-- one queue:
--   * fast path — an AFTER INSERT trigger enqueues the job + best-effort kicks
--     the edge fn via pg_net (guarded; never blocks the document insert).
--   * backbone — a pg_cron poller (_drain_ocr_jobs) that reclaims stale leases,
--     dead-letters exhausted jobs, and claims a config-bounded batch. Every
--     queued / stale-processing row is eventually drained, so a dropped kick
--     never strands a job (design §6.6).
--
-- Everything above the config layer is fixed; throughput/fairness/lease are
-- platform_config knobs (design §6a) read at runtime — scaling is a config
-- change, not a redeploy. pg_net / pg_cron are Supabase-managed and ABSENT from
-- the Docker harness, so every net/cron call is guarded by a pg_extension check
-- (the 0050 pattern); the queue logic itself is plain SQL and fully tested.

-- ---------------------------------------------------------------------------
-- _ocr_config — resolve a knob: per-org override → platform default row →
-- hard-coded fallback. Internal (SECURITY DEFINER); callers extract the scalar
-- with #>> '{}'.
-- ---------------------------------------------------------------------------
create or replace function public._ocr_config(p_org_id uuid, p_key text, p_default jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select value from public.platform_config where key = p_key and org_id = p_org_id),
    (select value from public.platform_config where key = p_key and org_id is null),
    p_default);
$$;

-- Discoverable platform defaults for the dispatch knobs (design §6a). Idempotent;
-- _ocr_config still falls back to the same hard-coded values if a row is absent.
insert into public.platform_config (org_id, key, value) values
  (null, 'ocr_poller_batch_size',     '25'::jsonb),
  (null, 'ocr_max_concurrent_global', '50'::jsonb),
  (null, 'ocr_max_per_shop_per_min',  '10'::jsonb),
  (null, 'ocr_job_lease_seconds',     '60'::jsonb),
  (null, 'ocr_max_attempts',          '3'::jsonb),
  (null, 'ocr_poller_interval_s',     '10'::jsonb)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- _ocr_dispatch_kick — best-effort pg_net nudge so the edge fn wakes without
-- waiting for the next poller tick. Guarded + swallow-all: the poller is the
-- authoritative drainer, so a missing extension / URL / transient error is a
-- non-event. Endpoint + shared token come from config (never a hard-coded
-- secret); unset → silent no-op.
-- ---------------------------------------------------------------------------
create or replace function public._ocr_dispatch_kick(p_job_id uuid)
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
      body    := pg_catalog.jsonb_build_object('job_id', p_job_id)
    );
  end if;
exception when others then
  -- Never let a kick failure surface — the poller backstops every job.
  return;
end;
$$;

-- ---------------------------------------------------------------------------
-- _enqueue_ocr_for_bono — AFTER INSERT on document. Bono-type + ocr_enabled
-- (per-org, default off = dark launch) → one queued ocr_job + a best-effort
-- kick. NEVER raises: a failure here must not roll back the document insert.
-- ---------------------------------------------------------------------------
create or replace function public._enqueue_ocr_for_bono()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bono_type uuid;
  v_org_id    uuid;
  v_enabled   boolean;
  v_job_id    uuid;
begin
  select id into v_bono_type from public.document_type where code = 'bono';
  if new.type_id is distinct from v_bono_type then
    return null;  -- only bono documents get OCR
  end if;

  select organization_id into v_org_id from public.shop where id = new.shop_id;
  v_enabled := coalesce((public._ocr_config(v_org_id, 'ocr_enabled', 'false'::jsonb) #>> '{}')::boolean, false);
  if not v_enabled then
    return null;  -- feature dark for this org
  end if;

  insert into public.ocr_job (shop_id, document_id, status)
  values (new.shop_id, new.id, 'queued')
  on conflict (document_id) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    perform public._ocr_dispatch_kick(v_job_id);
  end if;
  return null;
exception when others then
  -- The document must always persist; a dispatch hiccup is not the user's problem.
  return null;
end;
$$;

create trigger enqueue_ocr_after_document_insert
  after insert on public.document
  for each row execute function public._enqueue_ocr_for_bono();

-- ---------------------------------------------------------------------------
-- _drain_ocr_jobs — the pg_cron poller. One tick: reclaim → dead-letter →
-- claim a budget-bounded batch → kick each. Returns the number claimed.
-- Not callable by app roles (pg_cron / service-role only).
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
  -- 1. Reclaim stale leases: a crashed/timed-out worker's job returns to the pool.
  update public.ocr_job
     set status = 'queued', locked_at = null, updated_at = pg_catalog.now()
   where status = 'processing'
     and locked_at is not null
     and locked_at < pg_catalog.now() - pg_catalog.make_interval(secs => v_lease);

  -- 2. Dead-letter jobs that exhausted their attempts (never re-claimed below).
  update public.ocr_job
     set status = 'failed', locked_at = null, updated_at = pg_catalog.now(),
         last_error = coalesce(last_error, 'max attempts exceeded')
   where status = 'queued' and attempts >= v_max_att;

  -- 3. Global backpressure: only pull what the in-flight ceiling allows.
  select pg_catalog.count(*) into v_inflight from public.ocr_job where status = 'processing';
  v_budget := least(v_batch, greatest(v_global - v_inflight, 0));
  if v_budget <= 0 then
    return 0;
  end if;

  -- 4. Claim the batch. The candidate CTE enforces the per-shop cap DETERMIN-
  --    istically within a tick (raw SKIP LOCKED would let one tick over-claim a
  --    single shop, since every queued row sees the same pre-claim in-flight
  --    count); the compare-and-set `status='queued'` in the UPDATE keeps two
  --    concurrent pollers from double-claiming a row without SKIP LOCKED.
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
           attempts = j.attempts + 1, updated_at = pg_catalog.now()
     where j.id in (select id from eligible)
       and j.status = 'queued'
    returning j.id
  loop
    v_claimed := v_claimed + 1;
    perform public._ocr_dispatch_kick(r.id);
  end loop;

  return v_claimed;
end;
$$;

revoke all on function public._drain_ocr_jobs() from public;

-- ---------------------------------------------------------------------------
-- pg_cron schedule (when available). Skipped in the harness (no pg_cron);
-- Supabase-managed envs pre-install it. Interval is fixed at schedule time —
-- ocr_poller_interval_s documents intent; re-run this block to change cadence.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'ocr-drain',
      '10 seconds',
      $cmd$select public._drain_ocr_jobs()$cmd$
    );
  end if;
end
$$;
