-- 0048_capabilities.sql
--
-- Capability vocabulary per docs/roles-and-permissions.md. Existing
-- shop_role / organization_role tables stay; this layer adds:
--   * capability — the catalog of atomic capability codes the rest
--                   of the app gates on (sales.post, sales.void,
--                   inventory.product.edit, etc.).
--   * shop_role_capability — many-to-many between shop_role and
--                             capability. A shop_role accumulates
--                             its capability set from this table.
--   * organization_role_capability — same for org-level roles.
--
-- The function auth_user_shop_capabilities(p_shop_id) returns the
-- caller's effective capability set for a shop, merging direct
-- shop_membership and org-level escalation. Mobile reads this once
-- per session/shop-selection and caches it client-side.
--
-- Existing auth_can_post_shop / auth_has_shop_role / etc. are kept
-- unchanged — they still encode the right policy and many RPCs
-- consult them. The capability layer is additive: client-side UI
-- gating uses capabilities, backend RPC gating continues to use the
-- existing predicates until a follow-up pass swaps them over.
--
-- v1 capability set is documented in section 5 below.

-- 1. The catalog.

create table public.capability (
  code text primary key
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_capability_updated_at
before update on public.capability
for each row execute function public.set_updated_at();

-- 2. Role-capability maps. Composite primary keys ensure idempotent
--    re-application of the seed below.

create table public.shop_role_capability (
  role_id uuid not null references public.shop_role(id) on delete cascade,
  capability_code text not null references public.capability(code) on delete cascade,
  primary key (role_id, capability_code)
);

create table public.organization_role_capability (
  role_id uuid not null references public.organization_role(id) on delete cascade,
  capability_code text not null references public.capability(code) on delete cascade,
  primary key (role_id, capability_code)
);

-- 3. RPC: caller's effective capabilities for a shop.
--
-- Direct shop_role grants + organization-role escalation are
-- unioned and deduped. Returns jsonb array<text> for ergonomic
-- consumption from Dart (jsonDecode + Set<String>).

create or replace function public.auth_user_shop_capabilities(p_shop_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = ''
as $$
  with effective as (
    -- Direct shop membership
    select src.capability_code as cap_code
    from public.shop_membership sm
    join public.shop_role_capability src on src.role_id = sm.role_id
    where sm.shop_id = p_shop_id
      and sm.user_id = auth.uid()
      and sm.is_active
    union all
    -- Org-level escalation
    select orc.capability_code as cap_code
    from public.shop s
    join public.organization_membership om on om.organization_id = s.organization_id
    join public.organization_role_capability orc on orc.role_id = om.role_id
    where s.id = p_shop_id
      and om.user_id = auth.uid()
      and om.is_active
  )
  select coalesce(
    jsonb_agg(distinct cap_code order by cap_code),
    '[]'::jsonb
  )
  from effective;
$$;

revoke all on function public.auth_user_shop_capabilities(uuid) from public;
grant execute on function public.auth_user_shop_capabilities(uuid) to authenticated;

-- 4. Capability predicate helper for future RPC consumers.
--
-- A backend RPC that wants to gate on a specific capability (rather
-- than the coarse owner/cashier roles) can call:
--   if not public.auth_user_has_capability('sales.void', p_shop_id) then raise ...
--
-- For v1, posting RPCs continue using auth_can_post_shop /
-- auth_has_shop_role; this helper is here so the migration plan to
-- capability-aware gating is unblocked.

create or replace function public.auth_user_has_capability(
  p_capability text,
  p_shop_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.shop_membership sm
    join public.shop_role_capability src on src.role_id = sm.role_id
    where sm.shop_id = p_shop_id
      and sm.user_id = auth.uid()
      and sm.is_active
      and src.capability_code = p_capability
  )
  or exists (
    select 1
    from public.shop s
    join public.organization_membership om on om.organization_id = s.organization_id
    join public.organization_role_capability orc on orc.role_id = om.role_id
    where s.id = p_shop_id
      and om.user_id = auth.uid()
      and om.is_active
      and orc.capability_code = p_capability
  );
$$;

revoke all on function public.auth_user_has_capability(text, uuid) from public;
grant execute on function public.auth_user_has_capability(text, uuid) to authenticated;

-- 5. Seed: v1 capability catalog.
--
-- Capability codes follow the `<area>.<action>(.<scope>?)` shape so
-- they sort + filter by area in admin UIs. Keep this list aligned
-- with docs/roles-and-permissions.md §6.

insert into public.capability (code, label, description) values
  -- Sales
  ('sales.post',              'Post sales',                    'Create new sales at the counter.'),
  ('sales.history.view',      'View sales history',            'Read posted sales.'),
  ('sales.void',              'Void sales',                    'Owner-only — reverse a posted sale.'),
  ('sales.export',            'Export sales',                  'Download sale data (CSV/PDF) — web only.'),
  -- Receive
  ('receive.post',            'Post receives',                 'Record a bono.'),
  ('receive.history.view',    'View receive history',          'Read posted receives.'),
  ('receive.void',            'Void receives',                 'Owner-only — reverse a posted receive.'),
  -- Payment
  ('payment.post',            'Post payments',                 'In and out customer/supplier payments.'),
  ('payment.history.view',    'View payment history',          ''),
  -- Expense
  ('expense.post',            'Post expenses',                 ''),
  ('expense.history.view',    'View expense history',          ''),
  -- Inventory
  ('inventory.product.view',  'View products',                 ''),
  ('inventory.product.edit',  'Edit product fields',           'Rename, category, threshold, packaging.'),
  ('inventory.product.create','Create new products',           ''),
  ('inventory.product.activate','Activate from catalog',       'Pull a global catalog item into the shop.'),
  ('inventory.barcode.bind',  'Bind a barcode to a packaging', ''),
  ('inventory.adjustment.post','Post a stock adjustment',      'Owner-only — opening/correction/spoilage.'),
  -- People
  ('people.party.view',       'View customers and suppliers',  ''),
  ('people.party.create',     'Create new parties',            'Customer or supplier records.'),
  ('people.party.edit',       'Edit party contact info',       ''),
  ('people.party.opening_balance', 'Post opening balance',     'One-time during onboarding.'),
  -- Setup
  ('setup.shop.edit',         'Edit shop settings',            'Currency, timezone, language, etc.'),
  -- Dashboard
  ('dashboard.view',          'View dashboard',                'Today summary, low-stock count, balances.')
on conflict (code) do update set
  label = excluded.label,
  description = excluded.description,
  is_active = excluded.is_active;

-- 6. Seed: default role → capability assignments.
--
-- Cashier baseline: daily operations + party creation (per the
-- existing pattern where cashiers create customers/suppliers on the
-- fly during a sale).
-- Owner inherits everything cashier has + the owner-only set.
-- Org owner / Org admin get the full shop-level capability set
-- (they manage shops; v1.x will introduce a smaller org_admin
-- profile that doesn't include adjustment/void).

with cashier as (
  select id from public.shop_role where code = 'cashier'
), owner as (
  select id from public.shop_role where code = 'owner'
), cashier_caps(cap) as (values
  ('sales.post'),
  ('sales.history.view'),
  ('receive.post'),
  ('receive.history.view'),
  ('payment.post'),
  ('payment.history.view'),
  ('expense.post'),
  ('expense.history.view'),
  ('inventory.product.view'),
  ('inventory.product.activate'),
  ('people.party.view'),
  ('people.party.create'),
  ('people.party.edit'),
  ('dashboard.view')
), owner_caps(cap) as (values
  ('sales.post'),
  ('sales.history.view'),
  ('sales.void'),
  ('sales.export'),
  ('receive.post'),
  ('receive.history.view'),
  ('receive.void'),
  ('payment.post'),
  ('payment.history.view'),
  ('expense.post'),
  ('expense.history.view'),
  ('inventory.product.view'),
  ('inventory.product.edit'),
  ('inventory.product.create'),
  ('inventory.product.activate'),
  ('inventory.barcode.bind'),
  ('inventory.adjustment.post'),
  ('people.party.view'),
  ('people.party.create'),
  ('people.party.edit'),
  ('people.party.opening_balance'),
  ('setup.shop.edit'),
  ('dashboard.view')
)
insert into public.shop_role_capability (role_id, capability_code)
  select (select id from cashier), cap from cashier_caps
  union all
  select (select id from owner), cap from owner_caps
on conflict do nothing;

-- Org-level roles get the full shop-level capability set so an org
-- owner editing a shop on the web portal has the same reach as the
-- shop owner. v1.x will refine.

with org_owner as (
  select id from public.organization_role where code = 'org_owner'
), org_admin as (
  select id from public.organization_role where code = 'org_admin'
), all_shop_caps as (
  select code from public.capability where code like 'sales.%'
    or code like 'receive.%'
    or code like 'payment.%'
    or code like 'expense.%'
    or code like 'inventory.%'
    or code like 'people.%'
    or code like 'setup.%'
    or code like 'dashboard.%'
)
insert into public.organization_role_capability (role_id, capability_code)
  select (select id from org_owner), code from all_shop_caps
  union all
  select (select id from org_admin), code from all_shop_caps
on conflict do nothing;
