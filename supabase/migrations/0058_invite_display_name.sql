-- 0058_invite_display_name.sql
--
-- Lets the owner set the staff member's display name at invite time
-- so the portal shows readable names from the moment they're added,
-- instead of waiting for them to visit /setup and set their own.
--
-- Behavior:
--   * create_shop_invite gains a p_display_name parameter (nullable).
--     Stored on the shop_invite row.
--   * claim_pending_invites_for_me() now upserts the invite's
--     display_name into user_profile when the invitee doesn't have
--     a profile yet. Existing profiles are NEVER overwritten — the
--     user always wins over the owner once they've set their own.

-- ===========================================================================
-- 1. Schema: display_name on shop_invite
-- ===========================================================================

alter table public.shop_invite
  add column display_name text check (
    display_name is null or length(btrim(display_name)) > 0
  );

-- ===========================================================================
-- 2. create_shop_invite: drop+recreate with display_name
-- ===========================================================================

drop function if exists public.create_shop_invite(uuid, text, text, text);

create or replace function public.create_shop_invite(
  p_shop_id      uuid,
  p_phone        text,
  p_email        text,
  p_role_code    text,
  p_display_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone        text;
  v_email        text;
  v_display_name text;
  v_invite_id    uuid;
  v_existing     uuid;
begin
  if not public.auth_user_has_capability('setup.staff.invite', p_shop_id) then
    raise exception 'Not allowed to invite staff for this shop';
  end if;

  if p_role_code not in ('cashier', 'owner') then
    raise exception 'Invitable roles are cashier and owner in v1 (got %)', p_role_code;
  end if;

  v_phone := nullif(pg_catalog.btrim(p_phone), '');
  v_email := nullif(pg_catalog.lower(pg_catalog.btrim(p_email)), '');
  v_display_name := nullif(pg_catalog.btrim(p_display_name), '');

  if v_phone is null and v_email is null then
    raise exception 'Provide either a phone or an email';
  end if;
  if v_phone is not null and v_email is not null then
    raise exception 'Provide exactly one of phone or email, not both';
  end if;

  if v_phone is not null and not v_phone like '+%' then
    raise exception 'Phone must be E.164 (must start with +)';
  end if;

  if v_email is not null and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Email does not look valid';
  end if;

  -- Idempotent on (shop_id, phone) or (shop_id, email) for pending.
  if v_phone is not null then
    select id into v_existing
    from public.shop_invite
    where shop_id = p_shop_id
      and phone = v_phone
      and accepted_at is null;
  else
    select id into v_existing
    from public.shop_invite
    where shop_id = p_shop_id
      and email = v_email
      and accepted_at is null;
  end if;

  if v_existing is not null then
    -- Refresh expiry + update display_name on re-invite so a typo
    -- can be corrected by re-submitting the same form.
    update public.shop_invite
    set expires_at   = pg_catalog.now() + interval '7 days',
        display_name = coalesce(v_display_name, display_name)
    where id = v_existing;
    return v_existing;
  end if;

  insert into public.shop_invite (
    shop_id, phone, email, role_code, display_name, created_by
  )
  values (
    p_shop_id, v_phone, v_email, p_role_code, v_display_name, auth.uid()
  )
  returning id into v_invite_id;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'setup.staff.invite',
    p_entity_type  => 'shop_invite',
    p_entity_id    => v_invite_id,
    p_after        => pg_catalog.jsonb_build_object(
      'phone',        v_phone,
      'email',        v_email,
      'role_code',    p_role_code,
      'display_name', v_display_name
    )
  );

  return v_invite_id;
end;
$$;

revoke all on function public.create_shop_invite(uuid, text, text, text, text) from public;
grant execute on function public.create_shop_invite(uuid, text, text, text, text) to authenticated;

-- ===========================================================================
-- 3. claim_pending_invites_for_me: seed user_profile.display_name when empty
-- ===========================================================================

create or replace function public.claim_pending_invites_for_me()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_phone text;
  v_user_email text;
  v_user_id    uuid := auth.uid();
  v_count      int  := 0;
  v_invite     record;
  v_role_id    uuid;
  v_was_new    boolean;
begin
  if v_user_id is null then
    return 0;
  end if;

  select pg_catalog.lower(pg_catalog.btrim(u.email)),
         pg_catalog.btrim(u.phone)
  into v_user_email, v_user_phone
  from auth.users u
  where u.id = v_user_id;

  if (v_user_email is null or v_user_email = '')
     and (v_user_phone is null or v_user_phone = '') then
    return 0;
  end if;

  for v_invite in
    select id, shop_id, role_code, phone, email, display_name
    from public.shop_invite
    where accepted_at is null
      and expires_at >= pg_catalog.now()
      and (
        (phone is not null and phone = v_user_phone)
        or (email is not null and email = v_user_email)
      )
    for update
  loop
    select id into v_role_id
    from public.shop_role
    where code = v_invite.role_code;
    if v_role_id is null then
      continue;
    end if;

    v_was_new := true;
    insert into public.shop_membership (shop_id, user_id, role_id)
    values (v_invite.shop_id, v_user_id, v_role_id)
    on conflict (shop_id, user_id) do update
      set role_id    = excluded.role_id,
          is_active  = true,
          updated_at = pg_catalog.now();
    if exists (
      select 1 from public.shop_membership sm
      where sm.shop_id = v_invite.shop_id
        and sm.user_id = v_user_id
        and sm.created_at < pg_catalog.now() - interval '1 second'
    ) then
      v_was_new := false;
    end if;

    -- Seed user_profile from the invite's display_name when the
    -- user doesn't already have one. ON CONFLICT DO NOTHING is the
    -- key — the user always wins once they've set their own name.
    if v_invite.display_name is not null then
      insert into public.user_profile (user_id, display_name)
      values (v_user_id, v_invite.display_name)
      on conflict (user_id) do nothing;
    end if;

    update public.shop_invite
    set accepted_at         = pg_catalog.now(),
        accepted_by_user_id = v_user_id
    where id = v_invite.id;

    perform public._audit_log(
      p_shop_id     => v_invite.shop_id,
      p_action_code => 'setup.staff.join',
      p_entity_type => 'shop_invite',
      p_entity_id   => v_invite.id,
      p_after       => pg_catalog.jsonb_build_object(
        'role_code',    v_invite.role_code,
        'display_name', v_invite.display_name,
        'via',          case when v_invite.phone is not null then 'phone' else 'email' end
      )
    );

    if v_was_new then
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;
