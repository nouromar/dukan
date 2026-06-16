-- 0059_invite_dual_contact.sql
--
-- Allows a single shop_invite row to carry BOTH a phone and an email
-- so the cashier can sign in with whichever channel they prefer and
-- get auto-claimed. Previously the CHECK enforced exactly-one; this
-- loosens it to at-least-one.
--
-- claim_pending_invites_for_me() doesn't need to change — it already
-- matches on either channel and the new audit logic correctly
-- records which channel actually triggered the claim.

-- ===========================================================================
-- 1. Schema: relax the contact constraint
-- ===========================================================================

alter table public.shop_invite
  drop constraint shop_invite_exactly_one_contact;

alter table public.shop_invite
  add constraint shop_invite_at_least_one_contact
  check (phone is not null or email is not null);

-- ===========================================================================
-- 2. create_shop_invite: accept both; no XOR check
-- ===========================================================================
--
-- Idempotency: still keyed by (shop_id, phone) and (shop_id, email)
-- via the existing partial unique indexes. If an existing pending
-- invite already has the phone OR the email, we update that row
-- (refresh expiry + fill in any missing channel + overwrite name).
-- If two different pending invites exist (one keyed on the phone,
-- one on the email), we raise — the data model says one staff
-- member is one row, so the owner needs to resolve the conflict
-- (cancel one of the rows manually).

drop function if exists public.create_shop_invite(uuid, text, text, text, text);

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
  v_by_phone     uuid;
  v_by_email     uuid;
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
    raise exception 'Provide at least one of phone or email';
  end if;

  if v_phone is not null and not v_phone like '+%' then
    raise exception 'Phone must be E.164 (must start with +)';
  end if;

  if v_email is not null and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Email does not look valid';
  end if;

  -- Look up the pending invite (if any) keyed by either channel.
  if v_phone is not null then
    select id into v_by_phone
    from public.shop_invite
    where shop_id = p_shop_id
      and phone = v_phone
      and accepted_at is null;
  end if;
  if v_email is not null then
    select id into v_by_email
    from public.shop_invite
    where shop_id = p_shop_id
      and email = v_email
      and accepted_at is null;
  end if;

  if v_by_phone is not null and v_by_email is not null
     and v_by_phone <> v_by_email then
    raise exception
      'Different pending invites already exist for that phone and email — cancel one first';
  end if;

  v_existing := coalesce(v_by_phone, v_by_email);

  if v_existing is not null then
    -- Fill in any newly-provided channel + refresh expiry + name.
    update public.shop_invite
    set phone        = coalesce(v_phone, phone),
        email        = coalesce(v_email, email),
        display_name = coalesce(v_display_name, display_name),
        expires_at   = pg_catalog.now() + interval '7 days'
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
