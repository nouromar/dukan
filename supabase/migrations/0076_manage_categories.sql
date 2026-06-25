-- 0076_manage_categories.sql
--
-- Owner-managed categories (product + expense) from the mobile app.
--
-- Product categories (`category`) were global + platform-admin-only. This
-- migration adds a per-shop custom layer in the SAME table: a nullable
-- `shop_id` — NULL = global/platform-curated (unchanged, read-only to
-- owners), set = shop-owned (owner-editable). `shop_item.category_id` keeps
-- its single FK to `category(id)`; owners now create their own categories
-- alongside the global ones.
--
-- Expense categories (`expense_category`) are already per-shop and already
-- owner-writable via RLS; here we add idempotent RPCs so the mobile offline
-- queue can create/rename/hide them safely.
--
-- Gating: all 6 RPCs use `auth_can_manage_shop_setup` (owner / org / platform
-- — NOT cashier), matching the "config tables stay setup-only" rule from
-- 0027_create_party.sql. UI gates on a new capability `inventory.category.manage`.
--
-- Offline reconciliation: create_* RPCs take a CLIENT-supplied row id so the
-- optimistic local-mirror row and the eventual server row share one id (no
-- duplicate when the queued create posts). Idempotency also recorded in
-- `mutation_idempotency` (0074) keyed by client_op_id.

-- ---------------------------------------------------------------------------
-- 1. Capability + role assignment (owner-level)
-- ---------------------------------------------------------------------------

insert into public.capability (code, label, description) values
  ('inventory.category.manage', 'Manage categories',
   'Owner — create, rename, and hide product & expense categories.')
on conflict (code) do update set
  label = excluded.label,
  description = excluded.description,
  is_active = excluded.is_active;

insert into public.shop_role_capability (role_id, capability_code)
  select sr.id, 'inventory.category.manage'
  from public.shop_role sr
  where sr.code = 'owner'
on conflict do nothing;

insert into public.organization_role_capability (role_id, capability_code)
  select orl.id, 'inventory.category.manage'
  from public.organization_role orl
  where orl.code in ('org_owner', 'org_admin')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 2. Product category per-shop layer
-- ---------------------------------------------------------------------------

alter table public.category
  add column if not exists shop_id    uuid references public.shop(id) on delete cascade,
  add column if not exists created_by uuid references auth.users(id) on delete set null;

-- The original `code text not null unique` was a GLOBAL unique. Replace it
-- with scoped uniques so two shops can both have e.g. code 'cosmetics'.
alter table public.category drop constraint if exists category_code_key;

create unique index if not exists category_global_code_ux
  on public.category (code) where shop_id is null;
create unique index if not exists category_shop_code_ux
  on public.category (shop_id, code) where shop_id is not null;
create index if not exists category_shop_active_idx
  on public.category (shop_id, is_active) where shop_id is not null;

-- Cross-row integrity for the existing FK: a shop_item may reference a global
-- category (shop_id null) OR a category owned by its own shop — never another
-- shop's. (RPCs enforce this too; the trigger is the belt-and-suspenders.)
create or replace function public.enforce_shop_item_category_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cat_shop uuid;
begin
  if new.category_id is null then
    return new;
  end if;
  select shop_id into v_cat_shop
    from public.category where id = new.category_id;
  if v_cat_shop is not null and v_cat_shop <> new.shop_id then
    raise exception 'Category % does not belong to shop %',
      new.category_id, new.shop_id;
  end if;
  return new;
end;
$$;

drop trigger if exists shop_item_category_scope on public.shop_item;
create trigger shop_item_category_scope
  before insert or update of category_id on public.shop_item
  for each row execute function public.enforce_shop_item_category_scope();

-- ---------------------------------------------------------------------------
-- 3. RLS — owners read/write their own shop's categories; global stays
--    platform-managed (category_manage from 0006 is left in place).
-- ---------------------------------------------------------------------------

drop policy if exists category_select on public.category;
create policy category_select on public.category
  for select using (
    (is_active and (shop_id is null or public.auth_can_access_shop(shop_id)))
    or public.auth_is_platform_staff(null)
  );

create policy category_shop_insert on public.category
  for insert
  with check (shop_id is not null and public.auth_can_manage_shop_setup(shop_id));

create policy category_shop_update on public.category
  for update
  using (shop_id is not null and public.auth_can_manage_shop_setup(shop_id))
  with check (shop_id is not null and public.auth_can_manage_shop_setup(shop_id));
-- No DELETE policy: categories are hidden via is_active (FK is on delete restrict).

-- ---------------------------------------------------------------------------
-- 4. Shared slug helper — derive a valid `code` from a typed name.
-- ---------------------------------------------------------------------------

create or replace function public._category_slug(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when s ~ '^[a-z]' then s else 'cat_' || s end
  from (
    select pg_catalog.btrim(
      pg_catalog.regexp_replace(
        pg_catalog.lower(pg_catalog.btrim(coalesce(p_name, ''))),
        '[^a-z0-9]+', '_', 'g'
      ),
      '_'
    ) as s
  ) q;
$$;

-- ---------------------------------------------------------------------------
-- 5. Product category RPCs
-- ---------------------------------------------------------------------------

create or replace function public.create_shop_category(
  p_shop_id      uuid,
  p_category_id  uuid,   -- client-generated; optimistic id == server id
  p_name         text,
  p_client_op_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_base text;
  v_code text;
  v_i    integer := 1;
  v_cached text;
begin
  if p_client_op_id is not null then
    select return_value into v_cached
      from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'create_shop_category'
       and created_at > pg_catalog.now() - interval '1 hour';
    if found then
      return v_cached::uuid;
    end if;
  end if;

  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to manage categories for this shop';
  end if;

  v_name := nullif(pg_catalog.btrim(p_name), '');
  if v_name is null then
    raise exception 'Category name is required';
  end if;
  if p_category_id is null then
    raise exception 'Category id is required';
  end if;

  v_base := public._category_slug(v_name);
  v_code := v_base;
  while exists (
    select 1 from public.category
     where shop_id = p_shop_id and code = v_code
  ) loop
    v_i := v_i + 1;
    v_code := v_base || '_' || v_i;
  end loop;

  insert into public.category (id, shop_id, code, name, created_by)
  values (p_category_id, p_shop_id, v_code, v_name, auth.uid())
  on conflict (id) do nothing;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'create_shop_category', p_category_id::text)
    on conflict do nothing;
  end if;

  return p_category_id;
end;
$$;

revoke all on function public.create_shop_category(uuid, uuid, text, text) from public;
grant execute on function public.create_shop_category(uuid, uuid, text, text) to authenticated;


create or replace function public.rename_shop_category(
  p_shop_id      uuid,
  p_category_id  uuid,
  p_name         text,
  p_client_op_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id and client_op_id = p_client_op_id
       and rpc_name = 'rename_shop_category'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to manage categories for this shop';
  end if;

  v_name := nullif(pg_catalog.btrim(p_name), '');
  if v_name is null then
    raise exception 'Category name is required';
  end if;

  update public.category
     set name = v_name, updated_at = now()
   where id = p_category_id
     and shop_id = p_shop_id;   -- shop-owned only; global rows untouched
  if not found then
    raise exception 'Category not found in this shop';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'rename_shop_category', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.rename_shop_category(uuid, uuid, text, text) from public;
grant execute on function public.rename_shop_category(uuid, uuid, text, text) to authenticated;


create or replace function public.set_shop_category_active(
  p_shop_id      uuid,
  p_category_id  uuid,
  p_is_active    boolean,
  p_client_op_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id and client_op_id = p_client_op_id
       and rpc_name = 'set_shop_category_active'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to manage categories for this shop';
  end if;

  update public.category
     set is_active = coalesce(p_is_active, true), updated_at = now()
   where id = p_category_id
     and shop_id = p_shop_id;
  if not found then
    raise exception 'Category not found in this shop';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'set_shop_category_active', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.set_shop_category_active(uuid, uuid, boolean, text) from public;
grant execute on function public.set_shop_category_active(uuid, uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Expense category RPCs (table already owner-writable via RLS; these add
--    idempotency + code generation for the offline queue)
-- ---------------------------------------------------------------------------

create or replace function public.create_expense_category(
  p_shop_id      uuid,
  p_category_id  uuid,
  p_name         text,
  p_client_op_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_base text;
  v_code text;
  v_i    integer := 1;
  v_cached text;
begin
  if p_client_op_id is not null then
    select return_value into v_cached
      from public.mutation_idempotency
     where shop_id = p_shop_id and client_op_id = p_client_op_id
       and rpc_name = 'create_expense_category'
       and created_at > pg_catalog.now() - interval '1 hour';
    if found then
      return v_cached::uuid;
    end if;
  end if;

  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to manage categories for this shop';
  end if;

  v_name := nullif(pg_catalog.btrim(p_name), '');
  if v_name is null then
    raise exception 'Category name is required';
  end if;
  if p_category_id is null then
    raise exception 'Category id is required';
  end if;

  v_base := public._category_slug(v_name);
  v_code := v_base;
  while exists (
    select 1 from public.expense_category
     where shop_id = p_shop_id and code = v_code
  ) loop
    v_i := v_i + 1;
    v_code := v_base || '_' || v_i;
  end loop;

  insert into public.expense_category (id, shop_id, code, name, created_by)
  values (p_category_id, p_shop_id, v_code, v_name, auth.uid())
  on conflict (shop_id, id) do nothing;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'create_expense_category', p_category_id::text)
    on conflict do nothing;
  end if;

  return p_category_id;
end;
$$;

revoke all on function public.create_expense_category(uuid, uuid, text, text) from public;
grant execute on function public.create_expense_category(uuid, uuid, text, text) to authenticated;


create or replace function public.rename_expense_category(
  p_shop_id      uuid,
  p_category_id  uuid,
  p_name         text,
  p_client_op_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id and client_op_id = p_client_op_id
       and rpc_name = 'rename_expense_category'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to manage categories for this shop';
  end if;

  v_name := nullif(pg_catalog.btrim(p_name), '');
  if v_name is null then
    raise exception 'Category name is required';
  end if;

  update public.expense_category
     set name = v_name, updated_at = now()
   where id = p_category_id
     and shop_id = p_shop_id;
  if not found then
    raise exception 'Expense category not found in this shop';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'rename_expense_category', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.rename_expense_category(uuid, uuid, text, text) from public;
grant execute on function public.rename_expense_category(uuid, uuid, text, text) to authenticated;


create or replace function public.set_expense_category_active(
  p_shop_id      uuid,
  p_category_id  uuid,
  p_is_active    boolean,
  p_client_op_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id and client_op_id = p_client_op_id
       and rpc_name = 'set_expense_category_active'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to manage categories for this shop';
  end if;

  update public.expense_category
     set is_active = coalesce(p_is_active, true), updated_at = now()
   where id = p_category_id
     and shop_id = p_shop_id;
  if not found then
    raise exception 'Expense category not found in this shop';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'set_expense_category_active', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.set_expense_category_active(uuid, uuid, boolean, text) from public;
grant execute on function public.set_expense_category_active(uuid, uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. set_shop_item_category — reject another shop's category (scope check)
-- ---------------------------------------------------------------------------

create or replace function public.set_shop_item_category(
  p_shop_id       uuid,
  p_shop_item_id  uuid,
  p_category_id   uuid,
  p_client_op_id  text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cat_shop uuid;
  v_cat_active boolean;
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id and client_op_id = p_client_op_id
       and rpc_name = 'set_shop_item_category'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit this shop';
  end if;

  if p_category_id is not null then
    select shop_id, is_active into v_cat_shop, v_cat_active
      from public.category where id = p_category_id;
    if v_cat_active is null or not v_cat_active then
      raise exception 'Unknown category';
    end if;
    -- global (null) or owned by this shop; never another shop's
    if v_cat_shop is not null and v_cat_shop <> p_shop_id then
      raise exception 'Category does not belong to this shop';
    end if;
  end if;

  update public.shop_item
     set category_id = p_category_id,
         updated_at  = now()
   where shop_id = p_shop_id
     and id      = p_shop_item_id;
  if not found then
    raise exception 'Shop item not found in this shop';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'set_shop_item_category', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.set_shop_item_category(uuid, uuid, uuid, text) from public;
grant execute on function public.set_shop_item_category(uuid, uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. list_categories — global + caller's shop-scoped categories. Adds an
--    optional p_shop_id (kept as 2nd arg so existing 1-arg callers still
--    resolve and get global-only) and an is_custom flag for the UI badge.
-- ---------------------------------------------------------------------------

drop function if exists public.list_categories(text);

create or replace function public.list_categories(
  p_locale  text default 'en',
  p_shop_id uuid default null
)
returns table (
  id        uuid,
  code      text,
  name      text,
  is_custom boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
begin
  if v_locale = '' then
    v_locale := 'en';
  end if;

  return query
  select
    c.id,
    c.code,
    public.tr(c.name, c.name_translations, v_locale) as name,
    (c.shop_id is not null) as is_custom
  from public.category c
  where c.is_active
    and c.parent_id is null
    and (c.shop_id is null or c.shop_id = p_shop_id)
  order by
    (c.shop_id is not null) asc,                       -- global first
    c.sort_order asc,
    public.tr(c.name, c.name_translations, v_locale) asc;
end;
$$;

revoke all on function public.list_categories(text, uuid) from public;
grant execute on function public.list_categories(text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Delta payload — include shop-scoped product categories + shop_id so the
--    offline mirror stores them. (Global rows keep shop_id null.)
-- ---------------------------------------------------------------------------

create or replace function public._build_categories_payload(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense    jsonb;
  v_categories jsonb;
  v_units      jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_expense
  from (
    select ec.id as category_id, ec.shop_id, ec.code, ec.name, ec.is_active
    from public.expense_category ec
    where ec.shop_id = p_shop_id
      and (p_since is null or ec.updated_at > p_since)
      and (p_since is not null or ec.is_active)
  ) r;

  -- Product categories: global (shop_id null) + this shop's custom.
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_categories
  from (
    select c.id, c.shop_id, c.code, c.parent_id, c.name, c.sort_order, c.is_active
    from public.category c
    where (c.shop_id is null or c.shop_id = p_shop_id)
      and (p_since is null or c.updated_at > p_since)
      and (p_since is not null or c.is_active)
  ) r;

  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_units
  from (
    select u.code, u.default_label, u.is_active
    from public.unit u
    where (p_since is null or u.updated_at > p_since)
      and (p_since is not null or u.is_active)
  ) r;

  return jsonb_build_object(
    'expense_categories', v_expense,
    'categories',         v_categories,
    'units',              v_units
  );
end;
$$;

revoke all on function public._build_categories_payload(uuid, timestamptz) from public;
