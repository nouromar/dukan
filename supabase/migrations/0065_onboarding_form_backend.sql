-- Backend for the comprehensive shop-item onboarding form (mobile).
-- Per plan at /Users/nouromar/.claude/plans/linear-fluttering-hartmanis.md.
--
-- Adds:
--   1. shop_item.image_path — Storage path for the per-item photo.
--   2. audit action_code + capability for the new RPCs below.
--   3. set_supplier_item_unit_cost — owner-only RPC that records a
--      typical supplier cost without forcing a real receive. Needed
--      so the onboarding form can capture cost the shopkeeper knows
--      from memory.
--   4. find_similar_shop_items — read RPC that returns near-matches
--      within the caller's shop. Drives Section 1's "this looks like
--      X you already have" soft-warn dialog. Trigram similarity over
--      shop_item_alias.alias_text_norm (already indexed by 0007).
--   5. Storage bucket shop-item-images + RLS policies. Path layout
--      <shop_id>/items/<shop_item_id>/<filename>; auth_can_access_shop
--      checks the extracted shop_id from the path.
--
-- Existing primitives reused (no schema change):
--   * adjustment_reason 'opening' (seeded in 0002) — onboarding's
--     opening-stock capture calls post_inventory_adjustment with this.
--   * shop_item_alias / shop_item_barcode RPCs from earlier migrations.

-- ---------------------------------------------------------------------------
-- 1. shop_item.image_path
-- ---------------------------------------------------------------------------

alter table public.shop_item
  add column if not exists image_path text;

comment on column public.shop_item.image_path is
  'Optional Storage object path in shop-item-images bucket. Layout: <shop_id>/items/<shop_item_id>/<filename>. NULL = no photo captured.';

-- ---------------------------------------------------------------------------
-- 2. Audit action_code + capability for the new write RPC
-- ---------------------------------------------------------------------------

insert into public.audit_action_code
  (code, area, description, captures_before, captures_after, requires_reason)
values
  ('inventory.supplier_cost.set',
   'inventory',
   'Typical supplier cost recorded for a packaging (outside post_receive).',
   false, true, false)
on conflict (code) do update set
  description = excluded.description,
  is_active = true;

insert into public.capability (code, label, description) values
  ('inventory.supplier_cost.set',
   'Record typical supplier cost',
   'Owner-only — set a supplier''s expected per-pack cost outside a real receive.')
on conflict (code) do update set
  label = excluded.label,
  description = excluded.description,
  is_active = true;

-- Cashiers participate in onboarding (recording typical supplier
-- costs during the comprehensive item flow); the RPC body itself
-- gates on auth_can_post_shop (owner OR cashier) to match sibling
-- onboarding RPCs (create_shop_item, add_shop_item_alias, …).
with owner as (select id from public.shop_role where code = 'owner'),
     cashier as (select id from public.shop_role where code = 'cashier')
insert into public.shop_role_capability (role_id, capability_code)
  select owner.id, 'inventory.supplier_cost.set' from owner
  union all
  select cashier.id, 'inventory.supplier_cost.set' from cashier
on conflict do nothing;

with org_owner as (select id from public.organization_role where code = 'org_owner'),
     org_admin as (select id from public.organization_role where code = 'org_admin')
insert into public.organization_role_capability (role_id, capability_code)
  select org_owner.id, 'inventory.supplier_cost.set' from org_owner
  union all
  select org_admin.id, 'inventory.supplier_cost.set' from org_admin
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. set_supplier_item_unit_cost
-- ---------------------------------------------------------------------------
-- Upserts the (shop, supplier, packaging) → last_unit_cost row. Mirrors
-- the side-effect post_receive already produces, minus the stock
-- movement / txn / payment writes. last_received_at is set to now()
-- so the Receive screen pre-fill picks it up as the most recent.

create or replace function public.set_supplier_item_unit_cost(
  p_shop_id           uuid,
  p_party_id          uuid,
  p_shop_item_unit_id uuid,
  p_unit_cost         numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_party_kind text;
  v_unit_exists boolean;
  v_audit_after jsonb;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to set supplier cost for this shop';
  end if;

  if p_unit_cost is null or p_unit_cost < 0 then
    raise exception 'unit_cost must be >= 0';
  end if;

  -- Party must belong to this shop and be a supplier (or both).
  select pt.code
    into v_party_kind
    from public.party p
    join public.party_type pt on pt.id = p.type_id
   where p.shop_id = p_shop_id
     and p.id      = p_party_id
     and p.is_active;
  if v_party_kind is null then
    raise exception 'Party % not found in this shop', p_party_id;
  end if;
  if v_party_kind not in ('supplier', 'both') then
    raise exception 'Party % is not a supplier (kind=%)', p_party_id, v_party_kind;
  end if;

  -- Packaging must belong to this shop.
  select true into v_unit_exists
    from public.shop_item_unit
   where shop_id = p_shop_id and id = p_shop_item_unit_id;
  if not v_unit_exists then
    raise exception 'Packaging % not found in this shop', p_shop_item_unit_id;
  end if;

  insert into public.supplier_item_unit_cost (
    shop_id, party_id, shop_item_unit_id,
    last_unit_cost, last_received_at
  ) values (
    p_shop_id, p_party_id, p_shop_item_unit_id,
    p_unit_cost, pg_catalog.now()
  )
  on conflict (shop_id, party_id, shop_item_unit_id) do update
    set last_unit_cost   = excluded.last_unit_cost,
        last_received_at = excluded.last_received_at,
        updated_at       = pg_catalog.now();

  v_audit_after := pg_catalog.jsonb_build_object(
    'party_id',          p_party_id,
    'shop_item_unit_id', p_shop_item_unit_id,
    'unit_cost',         p_unit_cost,
    'via',               'manual_set'
  );
  perform public._audit_log(
    p_shop_id     => p_shop_id,
    p_action_code => 'inventory.supplier_cost.set',
    p_entity_type => 'supplier_item_unit_cost',
    p_entity_id   => p_shop_item_unit_id,
    p_after       => v_audit_after
  );
end;
$$;

revoke all on function public.set_supplier_item_unit_cost(uuid, uuid, uuid, numeric) from public;
grant execute on function public.set_supplier_item_unit_cost(uuid, uuid, uuid, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. find_similar_shop_items
-- ---------------------------------------------------------------------------
-- Returns up to 5 shop_items in the caller's shop whose aliases are
-- similar to the query string. Drives the Section 1 dedup soft-warn.
-- Trigram similarity is loose (> 0.3 default) so close-misspellings
-- and substrings both hit. Optional base_unit filter narrows the hit
-- list — onboarding usually knows the base unit by the time it runs
-- this check.

create or replace function public.find_similar_shop_items(
  p_shop_id        uuid,
  p_query          text,
  p_base_unit_code text default null,
  p_locale         text default 'en'
)
returns table (
  shop_item_id    uuid,
  display_name    text,
  base_unit_code  text,
  similarity      numeric
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_query text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_query, '')));
  v_locale text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to query items for this shop';
  end if;
  if v_query = '' then
    return;
  end if;
  if v_locale = '' then
    v_locale := 'en';
  end if;

  -- Trigram similarity over alias_text_norm. The `%` operator from
  -- pg_trgm can't be unqualified under an empty search_path, so we use
  -- the function form. Per-shop alias counts are small in v1 so a
  -- linear scan + filter is fine; the GIN index on alias_text_norm is
  -- still helpful for very large shops via planner choice.
  return query
  with ranked as (
    select
      sia.shop_item_id,
      max(extensions.similarity(sia.alias_text_norm, v_query)) as sim
    from public.shop_item_alias sia
    where sia.shop_id  = p_shop_id
      and sia.is_active
      and extensions.similarity(sia.alias_text_norm, v_query) > 0.3
    group by sia.shop_item_id
  )
  select
    si.id as shop_item_id,
    public.shop_item_display_name(si.id, v_locale) as display_name,
    si.base_unit_code,
    r.sim::numeric as similarity
  from ranked r
  join public.shop_item si on si.id = r.shop_item_id
  where si.shop_id = p_shop_id
    and si.is_active
    and (p_base_unit_code is null or si.base_unit_code = p_base_unit_code)
  order by r.sim desc, si.updated_at desc
  limit 5;
end;
$$;

revoke all on function public.find_similar_shop_items(uuid, text, text, text) from public;
grant execute on function public.find_similar_shop_items(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Storage bucket: shop-item-images
-- ---------------------------------------------------------------------------
-- Path layout: <shop_id>/items/<shop_item_id>/<filename>
-- Filename: image.<ext> matching jpg/jpeg/png/webp. Compression target
-- matches BonoImagePicker (~1600px / 70%) so 4 MB cap is generous.

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'shop-item-images',
  'shop-item-images',
  false,
  4194304,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  updated_at = pg_catalog.now();

create or replace function public.storage_object_shop_item_image_shop_id(p_name text)
returns uuid
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_match text[];
begin
  v_match := pg_catalog.regexp_match(
    p_name,
    '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/items/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/image\.(jpg|jpeg|png|webp)$',
    'i'
  );
  if v_match is null then
    return null;
  end if;
  return v_match[1]::uuid;
end;
$$;

create or replace function public.storage_object_can_read_shop_item_image(
  p_bucket_id text,
  p_name      text
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select p_bucket_id = 'shop-item-images'
    and public.storage_object_shop_item_image_shop_id(p_name) is not null
    and (
      public.auth_can_access_shop(public.storage_object_shop_item_image_shop_id(p_name))
      or public.auth_is_platform_staff(null)
    );
$$;

create or replace function public.storage_object_can_write_shop_item_image(
  p_bucket_id text,
  p_name      text
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select p_bucket_id = 'shop-item-images'
    and public.storage_object_shop_item_image_shop_id(p_name) is not null
    -- Reuse the post-shop predicate: anyone who can post in the shop
    -- (owners + cashiers) can attach a photo during item onboarding.
    and public.auth_can_post_shop(public.storage_object_shop_item_image_shop_id(p_name));
$$;

revoke all on function public.storage_object_shop_item_image_shop_id(text) from public;
revoke all on function public.storage_object_can_read_shop_item_image(text, text) from public;
revoke all on function public.storage_object_can_write_shop_item_image(text, text) from public;
grant execute on function public.storage_object_shop_item_image_shop_id(text) to authenticated;
grant execute on function public.storage_object_can_read_shop_item_image(text, text) to authenticated;
grant execute on function public.storage_object_can_write_shop_item_image(text, text) to authenticated;

drop policy if exists shop_item_images_select on storage.objects;
create policy shop_item_images_select
on storage.objects
for select
to authenticated
using (
  public.storage_object_can_read_shop_item_image(bucket_id, name)
);

drop policy if exists shop_item_images_insert on storage.objects;
create policy shop_item_images_insert
on storage.objects
for insert
to authenticated
with check (
  public.storage_object_can_write_shop_item_image(bucket_id, name)
);

drop policy if exists shop_item_images_update on storage.objects;
create policy shop_item_images_update
on storage.objects
for update
to authenticated
using (
  public.storage_object_can_write_shop_item_image(bucket_id, name)
)
with check (
  public.storage_object_can_write_shop_item_image(bucket_id, name)
);

drop policy if exists shop_item_images_delete on storage.objects;
create policy shop_item_images_delete
on storage.objects
for delete
to authenticated
using (
  -- Same predicate as write: anyone who can attach a photo can remove
  -- one. shop_item rows are seldom hard-deleted; orphan eviction is
  -- expected to be a manual back-office task in v1.
  public.storage_object_can_write_shop_item_image(bucket_id, name)
);
