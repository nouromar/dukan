create table public.location (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  kind_id uuid not null references public.location_kind(id) on delete restrict,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, name),
  unique (shop_id, id)
);

create trigger set_location_updated_at
before update on public.location
for each row execute function public.set_updated_at();

create table public.shop_setting (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  key text not null
    check (key = lower(key) and key ~ '^[a-z][a-z0-9_]*$'),
  value jsonb not null,
  source text not null default 'manual'
    check (source in ('template', 'manual', 'learned', 'system')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, key),
  unique (shop_id, id)
);

create trigger set_shop_setting_updated_at
before update on public.shop_setting
for each row execute function public.set_updated_at();

create table public.help_channel (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid references public.shop(id) on delete cascade,
  channel text not null check (channel in ('whatsapp', 'email')),
  value text not null check (length(btrim(value)) > 0),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, channel, value),
  unique (shop_id, id)
);

create trigger set_help_channel_updated_at
before update on public.help_channel
for each row execute function public.set_updated_at();

create table public.expense_category (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  code text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  name text not null check (length(btrim(name)) > 0),
  name_translations jsonb,
  is_active boolean not null default true,
  source_template_item_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, code),
  unique (shop_id, id)
);

create trigger set_expense_category_updated_at
before update on public.expense_category
for each row execute function public.set_updated_at();

create index location_shop_id_active_idx
  on public.location (shop_id, is_active);

create index shop_setting_shop_id_key_idx
  on public.shop_setting (shop_id, key);

create index help_channel_shop_id_active_idx
  on public.help_channel (shop_id, is_active, sort_order);

create index expense_category_shop_id_active_idx
  on public.expense_category (shop_id, is_active);

grant select, insert, update on
  public.location,
  public.shop_setting,
  public.help_channel,
  public.expense_category
to authenticated;

alter table public.location enable row level security;
alter table public.shop_setting enable row level security;
alter table public.help_channel enable row level security;
alter table public.expense_category enable row level security;

create policy location_select
on public.location
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy location_insert
on public.location
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy location_update
on public.location
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));

create policy shop_setting_select
on public.shop_setting
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy shop_setting_insert
on public.shop_setting
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy shop_setting_update
on public.shop_setting
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));

create policy help_channel_select
on public.help_channel
for select
using (
  shop_id is null
  or public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy help_channel_insert
on public.help_channel
for insert
with check (
  (shop_id is not null and public.auth_can_manage_shop_setup(shop_id))
  or public.auth_is_platform_staff('platform_admin')
);

create policy help_channel_update
on public.help_channel
for update
using (
  (shop_id is not null and public.auth_can_manage_shop_setup(shop_id))
  or public.auth_is_platform_staff('platform_admin')
)
with check (
  (shop_id is not null and public.auth_can_manage_shop_setup(shop_id))
  or public.auth_is_platform_staff('platform_admin')
);

create policy expense_category_select
on public.expense_category
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy expense_category_insert
on public.expense_category
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy expense_category_update
on public.expense_category
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));
