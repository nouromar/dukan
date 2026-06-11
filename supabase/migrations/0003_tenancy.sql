create table public.organization (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  plan_code text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_organization_updated_at
before update on public.organization
for each row execute function public.set_updated_at();

create table public.organization_membership (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organization(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references public.organization_role(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id),
  unique (organization_id, id)
);

create trigger set_organization_membership_updated_at
before update on public.organization_membership
for each row execute function public.set_updated_at();

create table public.shop (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organization(id) on delete restrict,
  name text not null check (length(btrim(name)) > 0),
  currency_code text not null references public.currency(code) on delete restrict,
  timezone text not null default 'Africa/Mogadishu',
  default_language_code text not null default 'en' references public.language(code) on delete restrict,
  setup_status text not null default 'not_started'
    check (setup_status in ('not_started', 'template_applied', 'opening_stock_done', 'ready')),
  setup_completed_at timestamptz,
  -- Set once the shopkeeper dismisses the optional item-onboarding
  -- step (data-model-v2 §11.10 T#154). NULL means the card still
  -- appears on Home; non-null means dismissed. Independent of
  -- setup_status — the shop is "ready" the moment template_applied
  -- completes; this flag only controls the post-setup nag card.
  onboarding_dismissed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id)
);

create trigger set_shop_updated_at
before update on public.shop
for each row execute function public.set_updated_at();

create table public.shop_membership (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references public.shop_role(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, user_id),
  unique (shop_id, id)
);

create trigger set_shop_membership_updated_at
before update on public.shop_membership
for each row execute function public.set_updated_at();

create table public.platform_membership (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null check (role_code in ('platform_admin', 'support_agent')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, role_code)
);

create trigger set_platform_membership_updated_at
before update on public.platform_membership
for each row execute function public.set_updated_at();

create index organization_membership_user_id_organization_id_idx
  on public.organization_membership (user_id, organization_id)
  where is_active;

create index organization_membership_organization_id_role_id_idx
  on public.organization_membership (organization_id, role_id)
  where is_active;

create index shop_organization_id_idx
  on public.shop (organization_id);

create index shop_membership_user_id_shop_id_idx
  on public.shop_membership (user_id, shop_id)
  where is_active;

create index shop_membership_shop_id_role_id_idx
  on public.shop_membership (shop_id, role_id)
  where is_active;

create index platform_membership_user_id_idx
  on public.platform_membership (user_id)
  where is_active;
