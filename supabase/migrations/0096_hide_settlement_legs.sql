-- 0096_hide_settlement_legs.sql
--
-- Walk-in cash sales record their till cash as a `payment` row with a NULL
-- party and no allocation (post_sale, 0010). 0087 already flags these with the
-- generated column `is_settlement_leg` (client_op_id like '%:payment') and
-- forbids voiding them standalone ("void via the sale instead"). But they still
-- leak into the payment history / Money In list and open a party-less "Money In"
-- detail — confusing, and the standalone VOID is a footgun.
--
-- This migration lets a shop hide them (DEFAULT hide) with a per-shop flag, and
-- teaches list_payments to honour it. Frontend mirrors the flag for its
-- offline-first local list; the detail screen already gates VOID on
-- is_settlement_leg (0087) once the mobile read populates it.
--
--   * shop.hide_settlement_legs boolean NOT NULL DEFAULT true — a plain,
--     support/admin-flippable column (no daily mobile toggle; config stays out
--     of the daily flow). Reaches the app via auth_controller.loadShops's
--     `from('shop').select(...)` and its offline cache.
--   * list_payments re-created: excludes settlement legs when the flag is on,
--     and now returns is_settlement_leg so the app can render them read-only in
--     show-mode. Every other filter/column is unchanged.

alter table public.shop
  add column if not exists hide_settlement_legs boolean not null default true;

-- ---------------------------------------------------------------------------
-- list_payments — re-created from 0040 with the settlement-leg filter + column.
-- The added return column (is_settlement_leg) changes the OUT row type, so the
-- old function must be dropped before re-creating (create-or-replace can't
-- change a function's return type).
-- ---------------------------------------------------------------------------

drop function if exists public.list_payments(
  uuid, timestamptz, int, timestamptz, timestamptz, uuid, char
);

create or replace function public.list_payments(
  p_shop_id    uuid,
  p_before     timestamptz default null,
  p_limit      int         default 50,
  p_date_from  timestamptz default null,
  p_date_to    timestamptz default null,
  p_party_id   uuid        default null,
  p_direction  char        default null
)
returns table (
  payment_id          uuid,
  occurred_at         timestamptz,
  created_at          timestamptz,
  party_id            uuid,
  party_name          text,
  amount              numeric,
  direction           char(1),
  payment_method_code text,
  notes               text,
  is_refund           boolean,
  is_settlement_leg   boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_hide boolean;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list payments for this shop';
  end if;
  if p_direction is not null and p_direction not in ('I', 'O') then
    raise exception 'Direction must be I, O, or null';
  end if;

  select s.hide_settlement_legs into v_hide
  from public.shop s where s.id = p_shop_id;
  v_hide := coalesce(v_hide, true);

  return query
  select
    p.id            as payment_id,
    p.occurred_at,
    p.created_at,
    p.party_id,
    party.name      as party_name,
    p.amount,
    p.direction,
    pm.code         as payment_method_code,
    p.notes,
    (p.refund_of_transaction_id is not null) as is_refund,
    p.is_settlement_leg
  from public.payment p
  left join public.party party on party.id = p.party_id
  left join public.payment_method pm on pm.id = p.method_id
  where p.shop_id = p_shop_id
    and (not v_hide or not p.is_settlement_leg)
    and (p_before    is null or p.occurred_at <  p_before)
    and (p_date_from is null or p.occurred_at >= p_date_from)
    and (p_date_to   is null or p.occurred_at <  p_date_to)
    and (p_party_id  is null or p.party_id = p_party_id)
    and (p_direction is null or p.direction = p_direction)
  order by p.occurred_at desc, p.id desc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_payments(uuid, timestamptz, int, timestamptz, timestamptz, uuid, char) from public;
grant execute on function public.list_payments(uuid, timestamptz, int, timestamptz, timestamptz, uuid, char) to authenticated;
