-- 0057_user_profile.sql
--
-- Per-user display name. Each auth.users row may have one
-- user_profile row holding a free-form display name the user picks
-- themselves. Read access is shared with anyone who is a member of
-- a shop the profiled user is also a member of — so owners see
-- their cashiers' names, cashiers see their colleagues, but cross-
-- org users remain anonymous to each other.
--
-- Why a new table vs. extending user_preference: user_preference is
-- "my own UI settings" (locale, theme, etc) and is strictly self-
-- only. user_profile is "things others may need to see about me"
-- (name today, avatar URL tomorrow, phone-display flag later) and
-- has a different RLS shape.

create table public.user_profile (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) > 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create trigger set_user_profile_updated_at
before update on public.user_profile
for each row execute function public.set_updated_at();

alter table public.user_profile enable row level security;

-- 1. Owner of the row reads + writes their own data.
create policy user_profile_self
on public.user_profile
for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- 2. Same-shop visibility — read only. Any signed-in user can
--    read the profile of someone they share at least one active
--    shop_membership with.
create policy user_profile_shared_shop_read
on public.user_profile
for select
using (
  exists (
    select 1
    from public.shop_membership viewer
    join public.shop_membership target
      on target.shop_id = viewer.shop_id
    where viewer.user_id = auth.uid()
      and viewer.is_active
      and target.user_id = user_profile.user_id
      and target.is_active
  )
);

grant select, insert, update on public.user_profile to authenticated;

comment on table public.user_profile is
  'Per-user display name + future profile fields. Self-edit; same-shop members can read.';
