-- 0055_invite_email_and_autoclaim.sql
--
-- Extends the #265 invite surface for the simplified onboarding flow.
-- See docs/staff-onboarding.md for the full story.
--
-- Changes:
--   1. shop_invite gains an `email` column. phone becomes nullable.
--      A CHECK enforces exactly one of (phone, email) is set per row.
--      Unique pending index added for email (mirrors the phone one).
--   2. New audit action code 'setup.staff.join' — emitted when a user
--      auto-claims a pending invite via the new RPC below.
--   3. create_shop_invite gets a 4th arg (email). Either phone or
--      email may be provided, not both. Signature change → drop+
--      recreate. Existing callers pass NULL for email.
--   4. NEW claim_pending_invites_for_me() RPC — called by mobile +
--      portal right after sign-in. Resolves the caller's identifiers
--      from auth.users (phone + email), finds matching pending
--      shop_invite rows, creates shop_membership for each, marks the
--      invites accepted, audit-logs the join. Returns the count.
--   5. accept_shop_invite is left in place but is now redundant —
--      the auto-claim path covers everything it did. Keep for any
--      legacy deep-link surface.

-- ===========================================================================
-- 1. Schema: email column + relax phone + CHECK + unique pending email index
-- ===========================================================================

alter table public.shop_invite
  alter column phone drop not null,
  add column email text check (
    email is null or length(btrim(email)) > 0
  );

-- Exactly one contact channel per invite row.
alter table public.shop_invite
  add constraint shop_invite_exactly_one_contact
  check (
    (phone is not null and email is null)
    or (phone is null and email is not null)
  );

-- Pending-invite uniqueness for email (mirrors the existing phone one).
create unique index shop_invite_pending_email_unique
  on public.shop_invite (shop_id, email)
  where accepted_at is null and email is not null;

-- Convenience index for the claim path's email-driven lookup.
create index shop_invite_email_pending_idx
  on public.shop_invite (email)
  where accepted_at is null and email is not null;

-- Owners + invitees-by-phone already covered by 0054 policies. Add
-- the email counterpart: an invitee may see their own email-keyed
-- invite from the JWT email claim, before they have shop access.
create policy shop_invite_select_by_email
on public.shop_invite
for select
using (
  accepted_at is null
  and email is not null
  and email = coalesce(current_setting('request.jwt.claim.email', true), '')
);

-- ===========================================================================
-- 2. Audit action code for the auto-claim path
-- ===========================================================================

insert into public.audit_action_code
  (code, area, description, captures_before, captures_after, requires_reason)
values
  ('setup.staff.join', 'setup', 'Staff member joined a shop via accepted invite',
   false, true, false)
on conflict (code) do nothing;

-- ===========================================================================
-- 3. create_shop_invite: drop+recreate with email support
-- ===========================================================================

drop function if exists public.create_shop_invite(uuid, text, text);

create or replace function public.create_shop_invite(
  p_shop_id   uuid,
  p_phone     text,
  p_email     text,
  p_role_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone     text;
  v_email     text;
  v_invite_id uuid;
  v_existing  uuid;
begin
  if not public.auth_user_has_capability('setup.staff.invite', p_shop_id) then
    raise exception 'Not allowed to invite staff for this shop';
  end if;

  if p_role_code not in ('cashier', 'owner') then
    raise exception 'Invitable roles are cashier and owner in v1 (got %)', p_role_code;
  end if;

  v_phone := nullif(pg_catalog.btrim(p_phone), '');
  v_email := nullif(pg_catalog.lower(pg_catalog.btrim(p_email)), '');

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
    update public.shop_invite
    set expires_at = pg_catalog.now() + interval '7 days'
    where id = v_existing;
    return v_existing;
  end if;

  insert into public.shop_invite (shop_id, phone, email, role_code, created_by)
  values (p_shop_id, v_phone, v_email, p_role_code, auth.uid())
  returning id into v_invite_id;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'setup.staff.invite',
    p_entity_type  => 'shop_invite',
    p_entity_id    => v_invite_id,
    p_after        => pg_catalog.jsonb_build_object(
      'phone',     v_phone,
      'email',     v_email,
      'role_code', p_role_code
    )
  );

  return v_invite_id;
end;
$$;

revoke all on function public.create_shop_invite(uuid, text, text, text) from public;
grant execute on function public.create_shop_invite(uuid, text, text, text) to authenticated;

-- ===========================================================================
-- 4. claim_pending_invites_for_me — the auto-claim path
-- ===========================================================================
--
-- Caller is any signed-in user. Reads their phone + email from
-- auth.users (security definer so the cross-schema read is allowed),
-- joins pending shop_invite rows, creates memberships idempotently.
-- Returns the number of NEW memberships created (existing ones don't
-- count even if their is_active flag was flipped back on).

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

  -- Lock the relevant invite rows so concurrent sign-ins don't
  -- double-create memberships.
  for v_invite in
    select id, shop_id, role_code, phone, email
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

    -- Track whether the membership is genuinely new for the return
    -- counter; the upsert reactivates any soft-revoked row too.
    v_was_new := true;
    insert into public.shop_membership (shop_id, user_id, role_id)
    values (v_invite.shop_id, v_user_id, v_role_id)
    on conflict (shop_id, user_id) do update
      set role_id    = excluded.role_id,
          is_active  = true,
          updated_at = pg_catalog.now();
    -- Postgres doesn't expose "did this insert vs update" cleanly
    -- without RETURNING + xmax checks. Cheaper: check separately.
    if exists (
      select 1 from public.shop_membership sm
      where sm.shop_id = v_invite.shop_id
        and sm.user_id = v_user_id
        and sm.created_at < pg_catalog.now() - interval '1 second'
    ) then
      v_was_new := false;
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
        'role_code', v_invite.role_code,
        'via',       case when v_invite.phone is not null then 'phone' else 'email' end
      )
    );

    if v_was_new then
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.claim_pending_invites_for_me() from public;
grant execute on function public.claim_pending_invites_for_me() to authenticated;
