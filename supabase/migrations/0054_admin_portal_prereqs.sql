-- ---------------------------------------------------------------------------
-- Shop admin portal prerequisites (#265).
-- ---------------------------------------------------------------------------
--
-- Four backend additions the portal needs before the web app can start
-- being built. Bundled into one migration because they're cheap and
-- share the same review surface:
--
--   1. user_preference table — cross-device per-user UI prefs (locale).
--      Mobile stores locale in SharedPreferences (device-local); portal
--      needs cross-device sync so when an owner switches from phone to
--      laptop, the portal opens in their preferred language.
--
--   2. New capabilities for portal-only actions (sales.export,
--      audit.view, audit.export, dashboard.view_org,
--      inventory.product.bulk_edit, people.statement.export,
--      money.payment.view, money.payment.reallocate, money.report.view,
--      money.cash.reconcile, setup.staff.invite,
--      setup.staff.assign_role, setup.branding.edit).
--
--   3. update_shop_settings RPC — audit-instrumented via the existing
--      setup.shop.edit action_code. Mobile's ShopApi.updateShopDefaults
--      migrates to use this RPC (done in this same task) so the audit
--      log captures setting edits regardless of surface.
--
--   4. shop_invite table + create_shop_invite + accept_shop_invite RPCs.
--      Powers the portal's "invite cashier" flow. Token in the SMS deep
--      link is the invite id; mobile onboarding accepts it.


-- ===========================================================================
-- 1. user_preference
-- ===========================================================================

create table public.user_preference (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  ui_locale   text not null default 'en' check (ui_locale in ('en', 'so')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger set_user_preference_updated_at
before update on public.user_preference
for each row execute function public.set_updated_at();

alter table public.user_preference enable row level security;

-- Each user reads + writes only their own row. No cross-user access.
create policy user_preference_select
on public.user_preference
for select
using (user_id = auth.uid());

create policy user_preference_insert
on public.user_preference
for insert
with check (user_id = auth.uid());

create policy user_preference_update
on public.user_preference
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

grant select, insert, update on public.user_preference to authenticated;


-- ===========================================================================
-- 2. New capabilities for portal-only actions
-- ===========================================================================

insert into public.capability (code, label, description) values
  -- Sales
  ('sales.export',                'Export sales data',                  'CSV / PDF of sales history and reports.'),
  -- Inventory
  ('inventory.product.bulk_edit', 'Bulk edit products',                 'Bulk price / threshold / category updates via the portal. Distinct from inventory.product.edit which is per-row.'),
  -- People
  ('people.statement.export',     'Export party statements',            'PDF + WhatsApp share for customer/supplier statements.'),
  -- Money
  ('money.payment.view',          'View payment history + allocations', 'Per-payment breakdown of which sales/receives it settled.'),
  ('money.payment.reallocate',    'Re-allocate a posted payment',       'Owner-only correction tool.'),
  ('money.report.view',           'View P&L and cash reports',          ''),
  ('money.cash.reconcile',        'Reconcile cash on hand',             'Owner posts a correction expense for the discrepancy.'),
  -- Setup
  ('setup.staff.invite',          'Invite staff via SMS deep link',     ''),
  ('setup.staff.assign_role',     'Assign or revoke staff roles',       ''),
  ('setup.branding.edit',         'Edit receipt template and branding', ''),
  -- Dashboard
  ('dashboard.view_org',          'View multi-shop org dashboard',      'Required for the "All shops" scope in the portal.'),
  -- Audit
  ('audit.view',                  'View audit log',                     'Portal feed of every state mutation.'),
  ('audit.export',                'Export audit log',                   'CSV download — owner-only.')
on conflict (code) do update set
  label = excluded.label,
  description = excluded.description,
  is_active = excluded.is_active;

-- Add the new capabilities to the owner role (the persona using the
-- portal). Cashier baseline is unchanged. Org-level role assignments
-- live in 0048's org section; the new dashboard.view_org code goes
-- there in v1.x when org roles get refined.

with owner as (
  select id from public.shop_role where code = 'owner'
), owner_new_caps(cap) as (values
  ('sales.export'),
  ('inventory.product.bulk_edit'),
  ('people.statement.export'),
  ('money.payment.view'),
  ('money.payment.reallocate'),
  ('money.report.view'),
  ('money.cash.reconcile'),
  ('setup.staff.invite'),
  ('setup.staff.assign_role'),
  ('setup.branding.edit'),
  ('dashboard.view_org'),
  ('audit.view'),
  ('audit.export')
)
insert into public.shop_role_capability (role_id, capability_code)
select (select id from owner), cap from owner_new_caps
on conflict do nothing;

-- Cashier gets money.payment.view (they already see payments via
-- payment.history.view, but the portal's allocation drill-down uses
-- the .view variant). Read-only, no escalation.
with cashier as (
  select id from public.shop_role where code = 'cashier'
)
insert into public.shop_role_capability (role_id, capability_code)
select (select id from cashier), 'money.payment.view'
on conflict do nothing;


-- ===========================================================================
-- 3. update_shop_settings RPC
-- ===========================================================================
--
-- Replaces the direct PATCH that mobile ShopApi.updateShopDefaults
-- did against the shop table. The portal will only edit settings
-- through this RPC; mobile is migrated to it in the same change set.
-- Audit-logged via setup.shop.edit (already in 0050).

create or replace function public.update_shop_settings(
  p_shop_id  uuid,
  p_settings jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before      jsonb;
  v_name        text;
  v_currency    text;
  v_lang        text;
  v_timezone    text;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can edit shop settings';
  end if;

  if p_settings is null
     or pg_catalog.jsonb_typeof(p_settings) <> 'object' then
    raise exception 'p_settings must be a JSON object';
  end if;

  -- Snapshot the row's pre-edit state for the audit log.
  select pg_catalog.jsonb_build_object(
    'name',                  s.name,
    'currency_code',         s.currency_code,
    'default_language_code', s.default_language_code,
    'timezone',              s.timezone
  )
  into v_before
  from public.shop s
  where s.id = p_shop_id;

  if v_before is null then
    raise exception 'Shop not found';
  end if;

  -- Extract any keys the caller supplied; null means "don't change."
  v_name     := nullif(pg_catalog.btrim(p_settings->>'name'), '');
  v_currency := nullif(p_settings->>'currency_code', '');
  v_lang     := nullif(p_settings->>'default_language_code', '');
  v_timezone := nullif(pg_catalog.btrim(p_settings->>'timezone'), '');

  if v_name is null
     and v_currency is null
     and v_lang is null
     and v_timezone is null then
    -- Nothing to do. Don't audit-log a no-op.
    return;
  end if;

  update public.shop
  set name                  = coalesce(v_name,     name),
      currency_code         = coalesce(v_currency, currency_code),
      default_language_code = coalesce(v_lang,     default_language_code),
      timezone              = coalesce(v_timezone, timezone),
      updated_at            = pg_catalog.now()
  where id = p_shop_id;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'setup.shop.edit',
    p_entity_type  => 'shop',
    p_entity_id    => p_shop_id,
    p_before       => v_before,
    p_after        => pg_catalog.jsonb_build_object(
      'name',                  coalesce(v_name,     v_before->>'name'),
      'currency_code',         coalesce(v_currency, v_before->>'currency_code'),
      'default_language_code', coalesce(v_lang,     v_before->>'default_language_code'),
      'timezone',              coalesce(v_timezone, v_before->>'timezone')
    )
  );
end;
$$;

revoke all on function public.update_shop_settings(uuid, jsonb) from public;
grant execute on function public.update_shop_settings(uuid, jsonb) to authenticated;


-- ===========================================================================
-- 4. shop_invite table + create/accept RPCs
-- ===========================================================================

create table public.shop_invite (
  id                  uuid primary key default extensions.gen_random_uuid(),
  shop_id             uuid not null references public.shop(id) on delete cascade,
  phone               text not null check (length(btrim(phone)) > 0),
  role_code           text not null references public.shop_role(code) on delete restrict,
  expires_at          timestamptz not null default (pg_catalog.now() + interval '7 days'),
  accepted_at         timestamptz,
  accepted_by_user_id uuid references auth.users(id) on delete set null,
  created_by          uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create trigger set_shop_invite_updated_at
  before update on public.shop_invite
  for each row execute function public.set_updated_at();

-- One PENDING invite per (shop, phone). Already-accepted invites are
-- historical and can coexist with a new one for the same phone.
create unique index shop_invite_pending_unique
  on public.shop_invite (shop_id, phone)
  where accepted_at is null;

create index shop_invite_phone_pending_idx
  on public.shop_invite (phone)
  where accepted_at is null;

alter table public.shop_invite enable row level security;

-- Owners of the shop see invites for that shop.
create policy shop_invite_select
on public.shop_invite
for select
using (public.auth_has_shop_role(shop_id, 'owner'));

-- Invitee may see their own invites by phone — needed for the mobile
-- onboarding accept flow, which doesn't have shop access yet.
-- (Phone is matched against the JWT's phone_number claim.)
create policy shop_invite_select_by_phone
on public.shop_invite
for select
using (
  accepted_at is null
  and phone = coalesce(current_setting('request.jwt.claim.phone_number', true), '')
);

-- Writes only via the RPCs below.
grant select on public.shop_invite to authenticated;

-- ---- create_shop_invite ----------------------------------------------------

create or replace function public.create_shop_invite(
  p_shop_id   uuid,
  p_phone     text,
  p_role_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone      text;
  v_invite_id  uuid;
  v_existing   uuid;
begin
  -- Capability check: caller must have setup.staff.invite on the shop.
  if not public.auth_user_has_capability('setup.staff.invite', p_shop_id) then
    raise exception 'Not allowed to invite staff for this shop';
  end if;

  -- Role must exist and be assignable. v1: cashier or owner only.
  if p_role_code not in ('cashier', 'owner') then
    raise exception 'Invitable roles are cashier and owner in v1 (got %)', p_role_code;
  end if;

  v_phone := nullif(pg_catalog.btrim(p_phone), '');
  if v_phone is null then
    raise exception 'Phone is required';
  end if;
  if not v_phone like '+%' then
    raise exception 'Phone must be E.164 (must start with +)';
  end if;

  -- If a pending invite already exists for this (shop, phone), return it.
  -- Idempotent on (shop_id, phone) for not-yet-accepted invites.
  select id into v_existing
  from public.shop_invite
  where shop_id = p_shop_id
    and phone = v_phone
    and accepted_at is null;

  if v_existing is not null then
    -- Refresh expires_at on the existing invite (resend semantics).
    update public.shop_invite
    set expires_at = pg_catalog.now() + interval '7 days'
    where id = v_existing;
    return v_existing;
  end if;

  insert into public.shop_invite (shop_id, phone, role_code, created_by)
  values (p_shop_id, v_phone, p_role_code, auth.uid())
  returning id into v_invite_id;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'setup.staff.invite',
    p_entity_type  => 'shop_invite',
    p_entity_id    => v_invite_id,
    p_after        => pg_catalog.jsonb_build_object(
      'phone',     v_phone,
      'role_code', p_role_code
    )
  );

  return v_invite_id;
end;
$$;

revoke all on function public.create_shop_invite(uuid, text, text) from public;
grant execute on function public.create_shop_invite(uuid, text, text) to authenticated;

-- ---- accept_shop_invite ----------------------------------------------------

create or replace function public.accept_shop_invite(
  p_invite_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite      public.shop_invite%rowtype;
  v_role_id     uuid;
  v_membership  uuid;
  v_caller_phone text;
begin
  select * into v_invite
  from public.shop_invite
  where id = p_invite_id
  for update;

  if v_invite.id is null then
    raise exception 'Invite not found';
  end if;
  if v_invite.accepted_at is not null then
    raise exception 'Invite already accepted';
  end if;
  if v_invite.expires_at < pg_catalog.now() then
    raise exception 'Invite has expired';
  end if;

  -- Caller's phone must match the invite's phone. Pulled from JWT.
  v_caller_phone := current_setting('request.jwt.claim.phone_number', true);
  if v_caller_phone is null
     or v_caller_phone = ''
     or v_caller_phone <> v_invite.phone then
    raise exception 'Invite phone does not match the signed-in user';
  end if;

  -- Resolve role id.
  select id into v_role_id from public.shop_role where code = v_invite.role_code;
  if v_role_id is null then
    raise exception 'Role not found: %', v_invite.role_code;
  end if;

  -- Create the shop_membership row (idempotent if it already exists).
  insert into public.shop_membership (shop_id, user_id, role_id)
  values (v_invite.shop_id, auth.uid(), v_role_id)
  on conflict (shop_id, user_id) do update
    set role_id    = excluded.role_id,
        is_active  = true,
        updated_at = pg_catalog.now()
  returning id into v_membership;

  update public.shop_invite
  set accepted_at         = pg_catalog.now(),
      accepted_by_user_id = auth.uid()
  where id = p_invite_id;

  return v_membership;
end;
$$;

revoke all on function public.accept_shop_invite(uuid) from public;
grant execute on function public.accept_shop_invite(uuid) to authenticated;
