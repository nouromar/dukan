-- 0051_audit_log_instrument_mvp.sql
--
-- MVP instrumentation of mutation RPCs to feed audit_log. Scoped to
-- the two RPCs the mobile inline cues consume:
--
--   * set_shop_item_unit_sale_price -> inventory.unit.price_edit
--     Powers "last edited by Cabdi yesterday" on Product detail's
--     price tile.
--   * update_party -> people.party.edit
--     Powers "contact info edited by Asha last week" on Party
--     detail's header.
--
-- The "voided by Asha 10 min ago" cue does NOT need audit_log -- the
-- existing txn.reverses_transaction_id chain + txn.created_by give
-- us the same data without a new write path. Migration 0052 exposes
-- that via a read RPC.
--
-- Wider instrumentation (post_sale, post_receive, post_payment,
-- post_expense, void_sale, void_receive, post_inventory_adjustment,
-- and ~20 catalog/setup mutations) ships when the shop admin portal
-- needs the full feed. Deferred from v1 mobile-only audit scope.

-- ---------------------------------------------------------------
-- set_shop_item_unit_sale_price -> inventory.unit.price_edit
-- ---------------------------------------------------------------
-- Adds one _audit_log call after the price update commits. Records
-- after_state only (the policy in audit_action_code drops
-- before_state for this code). shop_id is resolved from the
-- shop_item_unit row when the function lacks it directly.

create or replace function public.set_shop_item_unit_sale_price(
  p_shop_id           uuid,
  p_shop_item_unit_id uuid,
  p_sale_price        numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_shop_id is null or p_shop_item_unit_id is null then
    raise exception 'Shop id and shop_item_unit id are required';
  end if;

  if p_sale_price is not null and p_sale_price < 0 then
    raise exception 'Sale price cannot be negative';
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to update item prices for this shop';
  end if;

  update public.shop_item_unit
  set sale_price = p_sale_price,
      updated_at = pg_catalog.now()
  where shop_id = p_shop_id
    and id = p_shop_item_unit_id;

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'shop_item_unit not found in this shop';
  end if;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'inventory.unit.price_edit',
    p_entity_type  => 'shop_item_unit',
    p_entity_id    => p_shop_item_unit_id,
    p_after        => pg_catalog.jsonb_build_object('sale_price', p_sale_price)
  );
end;
$$;

revoke all on function public.set_shop_item_unit_sale_price(uuid, uuid, numeric) from public;
grant execute on function public.set_shop_item_unit_sale_price(uuid, uuid, numeric) to authenticated;

-- ---------------------------------------------------------------
-- update_party -> people.party.edit
-- ---------------------------------------------------------------
-- Captures before + after (name, phone). Phone redaction happens on
-- the read path -- see docs/audit-log.md §10.3.

create or replace function public.update_party(
  p_shop_id  uuid,
  p_party_id uuid,
  p_name     text,
  p_phone    text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name  text;
  v_phone text;
  v_before jsonb;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit parties for this shop';
  end if;

  v_name := nullif(pg_catalog.btrim(p_name), '');
  if v_name is null then
    raise exception 'Party name is required';
  end if;
  v_phone := nullif(pg_catalog.btrim(coalesce(p_phone, '')), '');

  -- Snapshot the row's pre-edit values for the audit before write.
  select pg_catalog.jsonb_build_object('name', p.name, 'phone', p.phone)
  into v_before
  from public.party p
  where p.shop_id = p_shop_id and p.id = p_party_id;

  update public.party
     set name       = v_name,
         phone      = v_phone,
         updated_at = now()
   where shop_id = p_shop_id
     and id      = p_party_id;
  if not found then
    raise exception 'Party not found in this shop';
  end if;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'people.party.edit',
    p_entity_type  => 'party',
    p_entity_id    => p_party_id,
    p_before       => v_before,
    p_after        => pg_catalog.jsonb_build_object('name', v_name, 'phone', v_phone)
  );
end;
$$;

revoke all on function public.update_party(uuid, uuid, text, text) from public;
grant execute on function public.update_party(uuid, uuid, text, text) to authenticated;
