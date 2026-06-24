-- 0075_unpaid_invoices_sync.sql
--
-- Cache the Payment screen's "outstanding invoices" list locally
-- so allocation works offline. Today `list_unpaid_invoices`
-- (from 0053) is called live per-party every time the allocation
-- sheet opens — when the device is offline the sheet shows
-- empty and the cashier can't allocate.
--
-- This migration adds:
--   _build_unpaid_invoices_payload  — helper returning ALL unpaid
--                                     invoices for the shop in
--                                     the shape the mobile mirror
--                                     ingests.
--   get_unpaid_invoices_delta       — exported RPC for SyncEngine.
--   patches get_shop_full_sync      — adds unpaid_invoices_payload
--                                     to the initial full sync.
--
-- Direction encoding mirrors the API: 'I' (inbound — customer
-- owes the shop, from a sale) and 'O' (outbound — shop owes the
-- party, from a receive). Stored as the same single-char string
-- the existing list_unpaid_invoices RPC accepts.
--
-- Delta semantics — every row carries `remaining` so the mobile
-- side can treat `remaining <= 0` as a tombstone (paid-off
-- invoice → DELETE from local mirror). This avoids needing
-- separate tombstone tracking.

create or replace function public._build_unpaid_invoices_payload(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  -- Unpaid sales (party owes the shop) + unpaid receives (shop
  -- owes the party). Mirrors the per-party shape from 0053's
  -- list_unpaid_invoices but un-scoped to all parties in the
  -- shop. Excludes voided txns (the reverses_transaction_id
  -- subquery) so paid-then-voided rows don't reappear.
  --
  -- p_since gates on `greatest(t.created_at, latest_alloc_at)` so
  -- rows whose remaining changed (newly allocated) re-appear in
  -- the delta. Full sync passes p_since = null → everything.
  with txn_payable as (
    select
      t.id                              as txn_id,
      t.shop_id,
      t.party_id,
      case when tt.code = 'sale' then 'I' else 'O' end as direction,
      t.occurred_at,
      t.created_at,
      t.total_amount                    as original_amount,
      t.document_id,
      coalesce(
        (
          select sum(pa.amount)
          from public.payment_allocation pa
          where pa.shop_id = t.shop_id
            and pa.transaction_id = t.id
        ),
        0
      )                                 as already_paid,
      coalesce(
        (
          select max(pa.created_at)
          from public.payment_allocation pa
          where pa.shop_id = t.shop_id
            and pa.transaction_id = t.id
        ),
        t.created_at
      )                                 as latest_change_at
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    join public.transaction_status ts on ts.id = t.status_id
    where t.shop_id   = p_shop_id
      and ts.code     = 'posted'
      and tt.code in ('sale', 'receive')
      and t.party_id is not null
      and t.reverses_transaction_id is null
      and not exists (
        select 1 from public.txn rev
        where rev.shop_id = t.shop_id
          and rev.reverses_transaction_id = t.id
      )
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.occurred_at_ms asc), '[]'::jsonb)
    into v_rows
  from (
    select
      shop_id,
      party_id,
      direction,
      txn_id,
      extract(epoch from occurred_at) * 1000 as occurred_at_ms,
      original_amount,
      already_paid,
      (original_amount - already_paid) as remaining,
      document_id,
      extract(epoch from latest_change_at) * 1000 as server_updated_at_ms
    from txn_payable
    where p_since is null or latest_change_at > p_since
  ) r;

  return jsonb_build_object('unpaid_invoices', v_rows);
end;
$$;

revoke all on function public._build_unpaid_invoices_payload(uuid, timestamptz) from public;


-- ---------------------------------------------------------------------------
-- get_unpaid_invoices_delta — public delta RPC for SyncEngine
-- ---------------------------------------------------------------------------

create or replace function public.get_unpaid_invoices_delta(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to access this shop';
  end if;
  if p_since is null then
    raise exception 'p_since is required (use get_shop_full_sync for an initial sync)';
  end if;

  insert into public.shop_sync_audit (shop_id, user_id, kind, notes)
    values (p_shop_id, v_uid, 'delta', 'unpaid_invoices');

  return public._build_unpaid_invoices_payload(p_shop_id, p_since)
       || jsonb_build_object(
            'server_now_ms', extract(epoch from now()) * 1000
          );
end;
$$;

revoke all on function public.get_unpaid_invoices_delta(uuid, timestamptz) from public;
grant execute on function public.get_unpaid_invoices_delta(uuid, timestamptz) to authenticated;


-- ---------------------------------------------------------------------------
-- Patch get_shop_full_sync to include unpaid_invoices_payload
-- ---------------------------------------------------------------------------

create or replace function public.get_shop_full_sync(
  p_shop_id uuid,
  p_force   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_recent   timestamptz;
  v_payload  jsonb;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to access this shop';
  end if;
  if v_uid is null then
    raise exception 'auth.uid() is null';
  end if;

  if not p_force then
    select max(ran_at) into v_recent
      from public.shop_sync_audit
     where shop_id = p_shop_id
       and user_id = v_uid
       and kind    = 'full';
    if v_recent is not null and v_recent > (now() - interval '24 hours') then
      raise exception
        'get_shop_full_sync rate-limited (last call %); pass p_force=true to override',
        v_recent;
    end if;
  end if;

  v_payload := jsonb_build_object(
    'items_payload',
      public._build_items_payload(p_shop_id, null),
    'parties_payload',
      public._build_parties_payload(p_shop_id, null),
    'categories_payload',
      public._build_categories_payload(p_shop_id, null),
    'transactions_payload',
      public._build_transactions_payload(p_shop_id, now() - interval '30 days', 500),
    'unpaid_invoices_payload',
      public._build_unpaid_invoices_payload(p_shop_id, null),
    'server_now_ms',
      extract(epoch from now()) * 1000
  );

  insert into public.shop_sync_audit (shop_id, user_id, kind, notes)
    values (p_shop_id, v_uid, 'full',
            case when p_force then 'forced' else null end);

  return v_payload;
end;
$$;
