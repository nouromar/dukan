create or replace function public.auth_has_org_role(
  p_organization_id uuid,
  p_role_code text
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_membership om
    join public.organization_role r on r.id = om.role_id
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and om.is_active
      and r.code = p_role_code
  );
$$;

create or replace function public.auth_can_access_organization(p_organization_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_membership om
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and om.is_active
  );
$$;

create or replace function public.auth_can_access_shop(p_shop_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.shop_membership sm
    where sm.shop_id = p_shop_id
      and sm.user_id = auth.uid()
      and sm.is_active
  )
  or exists (
    select 1
    from public.shop s
    join public.organization_membership om on om.organization_id = s.organization_id
    join public.organization_role r on r.id = om.role_id
    where s.id = p_shop_id
      and om.user_id = auth.uid()
      and om.is_active
      and r.code in ('org_owner', 'org_admin')
  );
$$;

create or replace function public.auth_has_shop_role(
  p_shop_id uuid,
  p_role_code text
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
    join public.shop_role r on r.id = sm.role_id
    where sm.shop_id = p_shop_id
      and sm.user_id = auth.uid()
      and sm.is_active
      and r.code = p_role_code
  )
  or (
    p_role_code = 'owner'
    and exists (
      select 1
      from public.shop s
      join public.organization_membership om on om.organization_id = s.organization_id
      join public.organization_role r on r.id = om.role_id
      where s.id = p_shop_id
        and om.user_id = auth.uid()
        and om.is_active
        and r.code = 'org_owner'
    )
  );
$$;

create or replace function public.auth_is_platform_staff(p_role_code text default null)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_membership pm
    where pm.user_id = auth.uid()
      and pm.is_active
      and (p_role_code is null or pm.role_code = p_role_code)
  );
$$;

create or replace function public.auth_can_manage_shop_setup(p_shop_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select public.auth_has_shop_role(p_shop_id, 'owner')
  or exists (
    select 1
    from public.shop s
    where s.id = p_shop_id
      and (
        public.auth_has_org_role(s.organization_id, 'org_owner')
        or public.auth_has_org_role(s.organization_id, 'org_admin')
      )
  )
  or public.auth_is_platform_staff(null);
$$;

create or replace function public.create_organization(
  p_organization_name text,
  p_shop_name text,
  p_currency_code text default 'USD',
  p_default_language_code text default 'en',
  p_timezone text default 'Africa/Mogadishu'
)
returns table (
  organization_id uuid,
  shop_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_org_owner_role_id uuid;
  v_shop_owner_role_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if length(btrim(p_organization_name)) = 0 then
    raise exception 'Organization name is required';
  end if;

  if length(btrim(p_shop_name)) = 0 then
    raise exception 'Shop name is required';
  end if;

  select id
  into v_org_owner_role_id
  from public.organization_role
  where code = 'org_owner' and is_active;

  select id
  into v_shop_owner_role_id
  from public.shop_role
  where code = 'owner' and is_active;

  if v_org_owner_role_id is null or v_shop_owner_role_id is null then
    raise exception 'Required owner roles are not seeded';
  end if;

  insert into public.organization (name, created_by)
  values (btrim(p_organization_name), v_user_id)
  returning id into organization_id;

  insert into public.organization_membership (organization_id, user_id, role_id)
  values (organization_id, v_user_id, v_org_owner_role_id);

  insert into public.shop (
    organization_id,
    name,
    currency_code,
    default_language_code,
    timezone,
    created_by
  )
  values (
    organization_id,
    btrim(p_shop_name),
    p_currency_code,
    p_default_language_code,
    p_timezone,
    v_user_id
  )
  returning id into shop_id;

  insert into public.shop_membership (shop_id, user_id, role_id)
  values (shop_id, v_user_id, v_shop_owner_role_id);

  return next;
end;
$$;

create or replace function public.create_shop(
  p_organization_id uuid,
  p_shop_name text,
  p_currency_code text default 'USD',
  p_default_language_code text default 'en',
  p_timezone text default 'Africa/Mogadishu'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_shop_id uuid;
  v_shop_owner_role_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not (
    public.auth_has_org_role(p_organization_id, 'org_owner')
    or public.auth_has_org_role(p_organization_id, 'org_admin')
  ) then
    raise exception 'Not allowed to create a shop for this organization';
  end if;

  if length(btrim(p_shop_name)) = 0 then
    raise exception 'Shop name is required';
  end if;

  select id
  into v_shop_owner_role_id
  from public.shop_role
  where code = 'owner' and is_active;

  if v_shop_owner_role_id is null then
    raise exception 'Required shop owner role is not seeded';
  end if;

  insert into public.shop (
    organization_id,
    name,
    currency_code,
    default_language_code,
    timezone,
    created_by
  )
  values (
    p_organization_id,
    btrim(p_shop_name),
    p_currency_code,
    p_default_language_code,
    p_timezone,
    v_user_id
  )
  returning id into v_shop_id;

  insert into public.shop_membership (shop_id, user_id, role_id)
  values (v_shop_id, v_user_id, v_shop_owner_role_id)
  on conflict (shop_id, user_id) do nothing;

  return v_shop_id;
end;
$$;

revoke all on function public.auth_has_org_role(uuid, text) from public;
revoke all on function public.auth_can_access_organization(uuid) from public;
revoke all on function public.auth_can_access_shop(uuid) from public;
revoke all on function public.auth_has_shop_role(uuid, text) from public;
revoke all on function public.auth_can_manage_shop_setup(uuid) from public;
revoke all on function public.auth_is_platform_staff(text) from public;
revoke all on function public.create_organization(text, text, text, text, text) from public;
revoke all on function public.create_shop(uuid, text, text, text, text) from public;

grant execute on function public.auth_has_org_role(uuid, text) to authenticated;
grant execute on function public.auth_can_access_organization(uuid) to authenticated;
grant execute on function public.auth_can_access_shop(uuid) to authenticated;
grant execute on function public.auth_has_shop_role(uuid, text) to authenticated;
grant execute on function public.auth_can_manage_shop_setup(uuid) to authenticated;
grant execute on function public.auth_is_platform_staff(text) to authenticated;
grant execute on function public.create_organization(text, text, text, text, text) to authenticated;
grant execute on function public.create_shop(uuid, text, text, text, text) to authenticated;

grant usage on schema public to anon, authenticated;

grant select on
  public.language,
  public.currency,
  public.unit,
  public.transaction_type,
  public.transaction_status,
  public.payment_method,
  public.party_type,
  public.document_type,
  public.ocr_status,
  public.organization_role,
  public.shop_role,
  public.adjustment_reason,
  public.location_kind,
  public.ref_translation
to anon, authenticated;

alter table public.language enable row level security;
alter table public.currency enable row level security;
alter table public.unit enable row level security;
alter table public.transaction_type enable row level security;
alter table public.transaction_status enable row level security;
alter table public.payment_method enable row level security;
alter table public.party_type enable row level security;
alter table public.document_type enable row level security;
alter table public.ocr_status enable row level security;
alter table public.organization_role enable row level security;
alter table public.shop_role enable row level security;
alter table public.adjustment_reason enable row level security;
alter table public.location_kind enable row level security;
alter table public.ref_translation enable row level security;

create policy language_select on public.language for select using (true);
create policy currency_select on public.currency for select using (true);
create policy unit_select on public.unit for select using (true);
create policy transaction_type_select on public.transaction_type for select using (true);
create policy transaction_status_select on public.transaction_status for select using (true);
create policy payment_method_select on public.payment_method for select using (true);
create policy party_type_select on public.party_type for select using (true);
create policy document_type_select on public.document_type for select using (true);
create policy ocr_status_select on public.ocr_status for select using (true);
create policy organization_role_select on public.organization_role for select using (true);
create policy shop_role_select on public.shop_role for select using (true);
create policy adjustment_reason_select on public.adjustment_reason for select using (true);
create policy location_kind_select on public.location_kind for select using (true);
create policy ref_translation_select on public.ref_translation for select using (true);

grant select, update on public.organization to authenticated;
grant select, insert, update on public.organization_membership to authenticated;
grant select, update on public.shop to authenticated;
grant select, insert, update on public.shop_membership to authenticated;
grant select on public.platform_membership to authenticated;

alter table public.organization enable row level security;
alter table public.organization_membership enable row level security;
alter table public.shop enable row level security;
alter table public.shop_membership enable row level security;
alter table public.platform_membership enable row level security;

create policy organization_select
on public.organization
for select
using (
  public.auth_can_access_organization(id)
  or public.auth_is_platform_staff(null)
);

create policy organization_update
on public.organization
for update
using (
  public.auth_has_org_role(id, 'org_owner')
  or public.auth_has_org_role(id, 'org_admin')
  or public.auth_is_platform_staff('platform_admin')
)
with check (
  public.auth_has_org_role(id, 'org_owner')
  or public.auth_has_org_role(id, 'org_admin')
  or public.auth_is_platform_staff('platform_admin')
);

create policy organization_membership_select
on public.organization_membership
for select
using (
  user_id = auth.uid()
  or public.auth_has_org_role(organization_id, 'org_owner')
  or public.auth_has_org_role(organization_id, 'org_admin')
  or public.auth_is_platform_staff(null)
);

create policy organization_membership_insert
on public.organization_membership
for insert
with check (
  public.auth_has_org_role(organization_id, 'org_owner')
  or public.auth_is_platform_staff('platform_admin')
);

create policy organization_membership_update
on public.organization_membership
for update
using (
  public.auth_has_org_role(organization_id, 'org_owner')
  or public.auth_is_platform_staff('platform_admin')
)
with check (
  public.auth_has_org_role(organization_id, 'org_owner')
  or public.auth_is_platform_staff('platform_admin')
);

create policy shop_select
on public.shop
for select
using (
  public.auth_can_access_shop(id)
  or public.auth_is_platform_staff(null)
);

create policy shop_update
on public.shop
for update
using (
  public.auth_has_shop_role(id, 'owner')
  or public.auth_has_org_role(organization_id, 'org_owner')
  or public.auth_has_org_role(organization_id, 'org_admin')
  or public.auth_is_platform_staff('platform_admin')
)
with check (
  public.auth_has_shop_role(id, 'owner')
  or public.auth_has_org_role(organization_id, 'org_owner')
  or public.auth_has_org_role(organization_id, 'org_admin')
  or public.auth_is_platform_staff('platform_admin')
);

create policy shop_membership_select
on public.shop_membership
for select
using (
  user_id = auth.uid()
  or public.auth_has_shop_role(shop_id, 'owner')
  or exists (
    select 1
    from public.shop s
    where s.id = shop_id
      and (
        public.auth_has_org_role(s.organization_id, 'org_owner')
        or public.auth_has_org_role(s.organization_id, 'org_admin')
      )
  )
  or public.auth_is_platform_staff(null)
);

create policy shop_membership_insert
on public.shop_membership
for insert
with check (
  public.auth_has_shop_role(shop_id, 'owner')
  or exists (
    select 1
    from public.shop s
    where s.id = shop_id
      and (
        public.auth_has_org_role(s.organization_id, 'org_owner')
        or public.auth_has_org_role(s.organization_id, 'org_admin')
      )
  )
  or public.auth_is_platform_staff('platform_admin')
);

create policy shop_membership_update
on public.shop_membership
for update
using (
  public.auth_has_shop_role(shop_id, 'owner')
  or exists (
    select 1
    from public.shop s
    where s.id = shop_id
      and (
        public.auth_has_org_role(s.organization_id, 'org_owner')
        or public.auth_has_org_role(s.organization_id, 'org_admin')
      )
  )
  or public.auth_is_platform_staff('platform_admin')
)
with check (
  public.auth_has_shop_role(shop_id, 'owner')
  or exists (
    select 1
    from public.shop s
    where s.id = shop_id
      and (
        public.auth_has_org_role(s.organization_id, 'org_owner')
        or public.auth_has_org_role(s.organization_id, 'org_admin')
      )
  )
  or public.auth_is_platform_staff('platform_admin')
);

create policy platform_membership_select
on public.platform_membership
for select
using (public.auth_is_platform_staff(null));
