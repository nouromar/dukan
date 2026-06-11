-- Alias + barcode mutations the product detail screen needs to support
-- inline chip-row management. Together with the existing
-- `add_shop_item_alias` RPC, this closes the v1 surface for managing
-- the search/identification metadata of a product.
--
-- All four RPCs are auth_can_post_shop (cashier-allowed): aliases and
-- barcodes are operational data a cashier learns mid-sale, not
-- configuration. The wider "owner-only" mutations (deactivate
-- packaging, set category) stay where they are.

-- ---- remove_shop_item_alias ------------------------------------------------

create or replace function public.remove_shop_item_alias(
  p_shop_id  uuid,
  p_alias_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_display boolean;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit aliases in this shop';
  end if;

  -- Refuse to remove the active display alias — every product needs
  -- one. The user must add a replacement (becoming the new display
  -- via add_shop_item_alias) before deleting the old one.
  select is_display into v_is_display
  from public.shop_item_alias
  where shop_id = p_shop_id and id = p_alias_id;
  if v_is_display is null then
    raise exception 'Alias not found in this shop';
  end if;
  if v_is_display then
    raise exception 'Cannot remove the display name; add a replacement first';
  end if;

  delete from public.shop_item_alias
  where shop_id = p_shop_id and id = p_alias_id;
end;
$$;

revoke all on function public.remove_shop_item_alias(uuid, uuid) from public;
grant execute on function public.remove_shop_item_alias(uuid, uuid) to authenticated;

-- ---- add_shop_item_barcode -------------------------------------------------
--
-- Barcodes attach to a packaging (shop_item_unit), not the product —
-- the 10 Kg bag has a different EAN than the 40 Kg sack. The
-- partial-unique index on (shop_id, shop_item_unit_id) where
-- is_primary already enforces at most one primary per packaging; we
-- atomically demote any prior primary in the same transaction when
-- the caller asks for a new primary.

create or replace function public.add_shop_item_barcode(
  p_shop_id           uuid,
  p_shop_item_unit_id uuid,
  p_barcode           text,
  p_is_primary        boolean default false,
  p_symbology         text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_barcode text;
  v_id      uuid;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit barcodes in this shop';
  end if;

  v_barcode := nullif(pg_catalog.btrim(p_barcode), '');
  if v_barcode is null then
    raise exception 'Barcode is required';
  end if;

  -- Verify the packaging belongs to this shop (composite-tenant
  -- integrity, not RLS-only).
  if not exists (
    select 1 from public.shop_item_unit
    where shop_id = p_shop_id and id = p_shop_item_unit_id
  ) then
    raise exception 'Packaging not found in this shop';
  end if;

  -- New primary → demote any sibling first so the partial-unique
  -- index stays consistent.
  if p_is_primary then
    update public.shop_item_barcode
       set is_primary = false,
           updated_at = now()
     where shop_id = p_shop_id
       and shop_item_unit_id = p_shop_item_unit_id
       and is_primary;
  end if;

  insert into public.shop_item_barcode (
    shop_id, shop_item_unit_id, barcode, symbology, is_primary, created_by
  )
  values (
    p_shop_id, p_shop_item_unit_id, v_barcode,
    nullif(pg_catalog.btrim(coalesce(p_symbology, '')), ''),
    p_is_primary, auth.uid()
  )
  on conflict (shop_id, shop_item_unit_id, barcode) do update
     set is_active = true,
         is_primary = excluded.is_primary or public.shop_item_barcode.is_primary,
         updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.add_shop_item_barcode(uuid, uuid, text, boolean, text) from public;
grant execute on function public.add_shop_item_barcode(uuid, uuid, text, boolean, text) to authenticated;

-- ---- remove_shop_item_barcode ----------------------------------------------

create or replace function public.remove_shop_item_barcode(
  p_shop_id    uuid,
  p_barcode_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit barcodes in this shop';
  end if;

  delete from public.shop_item_barcode
  where shop_id = p_shop_id and id = p_barcode_id;
end;
$$;

revoke all on function public.remove_shop_item_barcode(uuid, uuid) from public;
grant execute on function public.remove_shop_item_barcode(uuid, uuid) to authenticated;

-- ---- set_primary_shop_item_barcode -----------------------------------------
--
-- Atomically promotes one barcode to primary and demotes the prior
-- primary (if any) within the same packaging. Idempotent on the
-- already-primary case.

create or replace function public.set_primary_shop_item_barcode(
  p_shop_id    uuid,
  p_barcode_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unit_id uuid;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit barcodes in this shop';
  end if;

  select shop_item_unit_id into v_unit_id
  from public.shop_item_barcode
  where shop_id = p_shop_id and id = p_barcode_id;
  if v_unit_id is null then
    raise exception 'Barcode not found in this shop';
  end if;

  update public.shop_item_barcode
     set is_primary = false,
         updated_at = now()
   where shop_id = p_shop_id
     and shop_item_unit_id = v_unit_id
     and id <> p_barcode_id
     and is_primary;

  update public.shop_item_barcode
     set is_primary = true,
         updated_at = now()
   where shop_id = p_shop_id
     and id = p_barcode_id;
end;
$$;

revoke all on function public.set_primary_shop_item_barcode(uuid, uuid) from public;
grant execute on function public.set_primary_shop_item_barcode(uuid, uuid) to authenticated;
