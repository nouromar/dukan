-- 0074_mutation_client_op_id.sql
--
-- #389: add optional `p_client_op_id text` to 10 admin-side
-- mutation RPCs so the mobile offline queue (#367) can retry
-- them safely. Posts (post_sale / post_receive / post_payment /
-- post_expense) already had idempotency via the per-row
-- client_op_id column on `txn` + `payment`. This migration
-- generalises the pattern for mutation RPCs that don't have a
-- natural "row I created" to dedupe against — we record the
-- (shop_id, client_op_id) pair in a small audit table and
-- short-circuit duplicate calls within a 1h window.
--
-- New table `mutation_idempotency` retains entries for ~24h
-- (manual prune for now; pg_cron later). RLS-protected: members
-- can SELECT rows for shops they belong to (for debugging); no
-- direct DML — only the SECURITY DEFINER RPCs write.
--
-- Backwards-compatible: each function appends `p_client_op_id
-- text default null` as the LAST parameter. Current mobile
-- builds that don't pass it keep working unchanged.
--
-- Pattern per function:
--   1. Early return on duplicate (cached return value if any).
--   2. Existing logic.
--   3. INSERT idempotency row with the returned value.
--
-- 10 RPCs touched:
--   add_shop_item_alias            (returns uuid)
--   set_shop_item_unit_sale_price  (returns void)
--   set_shop_item_unit_default_flags (returns void)
--   set_shop_item_category         (returns void)
--   remove_or_disable_shop_item_unit (returns text 'removed'/'disabled')
--   remove_shop_item_alias         (returns void)
--   add_shop_item_barcode          (returns uuid)
--   remove_shop_item_barcode       (returns void)
--   set_primary_shop_item_barcode  (returns void)
--   update_party                   (returns void)

-- ---------------------------------------------------------------------------
-- mutation_idempotency table
-- ---------------------------------------------------------------------------

create table public.mutation_idempotency (
  shop_id      uuid not null references public.shop(id) on delete cascade,
  client_op_id text not null,
  rpc_name     text not null,
  return_value text,
  created_at   timestamptz not null default now(),
  primary key (shop_id, client_op_id)
);

create index mutation_idempotency_created_at_idx
  on public.mutation_idempotency (created_at);

comment on table public.mutation_idempotency is
  'Idempotency keys for admin-side mutation RPCs so the mobile '
  'offline queue can retry safely. Rows older than 24h can be '
  'pruned (manual cron for now).';

alter table public.mutation_idempotency enable row level security;

-- SELECT: members of the shop (debugging surface; the RPC body
-- itself doesn't go through this policy because it's SECURITY
-- DEFINER).
create policy mutation_idempotency_select on public.mutation_idempotency
  for select to authenticated
  using (public.auth_can_access_shop(shop_id));

-- No INSERT/UPDATE/DELETE policy — only the SECURITY DEFINER
-- RPCs write here.


-- ---------------------------------------------------------------------------
-- add_shop_item_alias (returns uuid)
-- ---------------------------------------------------------------------------

drop function if exists public.add_shop_item_alias(uuid, uuid, text, text, boolean, text);

create or replace function public.add_shop_item_alias(
  p_shop_id        uuid,
  p_shop_item_id   uuid,
  p_alias_text     text,
  p_language_code  text default null,
  p_is_display     boolean default false,
  p_source         text default 'manual',
  p_client_op_id   text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alias_id     uuid;
  v_alias_text   text;
  v_cached       text;
begin
  if p_client_op_id is not null then
    select return_value into v_cached
      from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'add_shop_item_alias'
       and created_at > pg_catalog.now() - interval '1 hour';
    if found then
      return v_cached::uuid;
    end if;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to add aliases for this shop';
  end if;

  v_alias_text := pg_catalog.btrim(coalesce(p_alias_text, ''));
  if v_alias_text = '' then
    raise exception 'Alias text is required';
  end if;

  if p_source not in ('manual', 'ocr_correction', 'learned') then
    raise exception 'source must be one of manual, ocr_correction, learned';
  end if;

  if not exists (
    select 1 from public.shop_item
    where id = p_shop_item_id and shop_id = p_shop_id
  ) then
    raise exception 'shop_item % not found in shop %', p_shop_item_id, p_shop_id;
  end if;

  if p_is_display then
    update public.shop_item_alias
       set is_display = false
     where shop_id = p_shop_id
       and shop_item_id = p_shop_item_id
       and language_code is not distinct from p_language_code
       and is_display;
  end if;

  insert into public.shop_item_alias (
    shop_id, shop_item_id, alias_text, language_code,
    is_display, source, created_by
  )
  values (
    p_shop_id, p_shop_item_id, v_alias_text, p_language_code,
    p_is_display, p_source, auth.uid()
  )
  on conflict (shop_id, shop_item_id, language_code, alias_text_norm)
  do update set
    is_display = excluded.is_display,
    source = excluded.source,
    is_active = true,
    updated_at = now()
  returning id into v_alias_id;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'add_shop_item_alias', v_alias_id::text)
    on conflict do nothing;
  end if;

  return v_alias_id;
end;
$$;

revoke all on function public.add_shop_item_alias(
  uuid, uuid, text, text, boolean, text, text
) from public;
grant execute on function public.add_shop_item_alias(
  uuid, uuid, text, text, boolean, text, text
) to authenticated;


-- ---------------------------------------------------------------------------
-- set_shop_item_unit_sale_price (returns void)
-- ---------------------------------------------------------------------------

drop function if exists public.set_shop_item_unit_sale_price(uuid, uuid, numeric);

create or replace function public.set_shop_item_unit_sale_price(
  p_shop_id           uuid,
  p_shop_item_unit_id uuid,
  p_sale_price        numeric,
  p_client_op_id      text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'set_shop_item_unit_sale_price'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if p_shop_id is null or p_shop_item_unit_id is null then
    raise exception 'Shop id and shop_item_unit id are required';
  end if;

  if p_sale_price is not null and p_sale_price < 0 then
    raise exception 'Sale price cannot be negative';
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to update item prices for this shop';
  end if;

  update public.shop_item_unit
     set sale_price = p_sale_price,
         updated_at = pg_catalog.now()
   where shop_id = p_shop_id
     and id = p_shop_item_unit_id;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'shop_item_unit not found in this shop';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'set_shop_item_unit_sale_price', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.set_shop_item_unit_sale_price(
  uuid, uuid, numeric, text
) from public;
grant execute on function public.set_shop_item_unit_sale_price(
  uuid, uuid, numeric, text
) to authenticated;


-- ---------------------------------------------------------------------------
-- set_shop_item_unit_default_flags (returns void)
-- ---------------------------------------------------------------------------

drop function if exists public.set_shop_item_unit_default_flags(
  uuid, uuid, boolean, boolean
);

create or replace function public.set_shop_item_unit_default_flags(
  p_shop_id            uuid,
  p_shop_item_unit_id  uuid,
  p_is_default_sale    boolean,
  p_is_default_receive boolean,
  p_client_op_id       text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop_item_id uuid;
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'set_shop_item_unit_default_flags'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if p_shop_id is null or p_shop_item_unit_id is null then
    raise exception 'Shop id and shop_item_unit id are required';
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception
      'Not allowed to update default packaging flags for this shop';
  end if;

  select shop_item_id into v_shop_item_id
    from public.shop_item_unit
   where shop_id = p_shop_id
     and id = p_shop_item_unit_id;

  if v_shop_item_id is null then
    raise exception 'shop_item_unit not found in this shop';
  end if;

  if p_is_default_sale then
    update public.shop_item_unit
       set is_default_sale = false,
           updated_at = pg_catalog.now()
     where shop_id = p_shop_id
       and shop_item_id = v_shop_item_id
       and id <> p_shop_item_unit_id
       and is_default_sale;
  end if;

  if p_is_default_receive then
    update public.shop_item_unit
       set is_default_receive = false,
           updated_at = pg_catalog.now()
     where shop_id = p_shop_id
       and shop_item_id = v_shop_item_id
       and id <> p_shop_item_unit_id
       and is_default_receive;
  end if;

  update public.shop_item_unit
     set is_default_sale = p_is_default_sale,
         is_default_receive = p_is_default_receive,
         updated_at = pg_catalog.now()
   where shop_id = p_shop_id
     and id = p_shop_item_unit_id;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'set_shop_item_unit_default_flags', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.set_shop_item_unit_default_flags(
  uuid, uuid, boolean, boolean, text
) from public;
grant execute on function public.set_shop_item_unit_default_flags(
  uuid, uuid, boolean, boolean, text
) to authenticated;


-- ---------------------------------------------------------------------------
-- set_shop_item_category (returns void)
-- ---------------------------------------------------------------------------

drop function if exists public.set_shop_item_category(uuid, uuid, uuid);

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
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'set_shop_item_category'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit this shop';
  end if;

  if p_category_id is not null then
    if not exists (
      select 1 from public.category where id = p_category_id and is_active
    ) then
      raise exception 'Unknown category';
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
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'set_shop_item_category', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.set_shop_item_category(uuid, uuid, uuid, text) from public;
grant execute on function public.set_shop_item_category(uuid, uuid, uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- remove_or_disable_shop_item_unit (returns text 'removed' | 'disabled')
-- ---------------------------------------------------------------------------

drop function if exists public.remove_or_disable_shop_item_unit(uuid, uuid);

create or replace function public.remove_or_disable_shop_item_unit(
  p_shop_id           uuid,
  p_shop_item_unit_id uuid,
  p_client_op_id      text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found    boolean := false;
  v_is_base  boolean;
  v_has_refs boolean;
  v_cached   text;
  v_result   text;
begin
  if p_client_op_id is not null then
    select return_value into v_cached
      from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'remove_or_disable_shop_item_unit'
       and created_at > pg_catalog.now() - interval '1 hour';
    if found then
      return v_cached;
    end if;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit this shop';
  end if;

  select true,
         (siu.conversion_to_base = 1
            and siu.unit_code = si.base_unit_code)
    into v_found, v_is_base
    from public.shop_item_unit siu
    join public.shop_item si on si.id = siu.shop_item_id
   where siu.shop_id = p_shop_id
     and siu.id      = p_shop_item_unit_id;

  if not v_found then
    raise exception 'Packaging not found in this shop';
  end if;
  if v_is_base then
    raise exception 'Cannot remove the base packaging';
  end if;

  select exists (
    select 1
      from public.transaction_line
     where shop_id           = p_shop_id
       and shop_item_unit_id = p_shop_item_unit_id
  ) into v_has_refs;

  if v_has_refs then
    update public.shop_item_unit
       set is_active          = false,
           is_default_sale    = false,
           is_default_receive = false,
           updated_at         = now()
     where shop_id = p_shop_id
       and id      = p_shop_item_unit_id;
    v_result := 'disabled';
  else
    delete from public.shop_item_unit
     where shop_id = p_shop_id
       and id      = p_shop_item_unit_id;
    v_result := 'removed';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'remove_or_disable_shop_item_unit', v_result)
    on conflict do nothing;
  end if;

  return v_result;
end;
$$;

revoke all on function public.remove_or_disable_shop_item_unit(uuid, uuid, text) from public;
grant execute on function public.remove_or_disable_shop_item_unit(uuid, uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- remove_shop_item_alias (returns void)
-- ---------------------------------------------------------------------------

drop function if exists public.remove_shop_item_alias(uuid, uuid);

create or replace function public.remove_shop_item_alias(
  p_shop_id      uuid,
  p_alias_id     uuid,
  p_client_op_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_display boolean;
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'remove_shop_item_alias'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit aliases in this shop';
  end if;

  select is_display into v_is_display
    from public.shop_item_alias
   where shop_id = p_shop_id and id = p_alias_id;
  if v_is_display is null then
    raise exception 'Alias not found in this shop';
  end if;
  if v_is_display then
    raise exception 'Cannot remove the display name; add a replacement first';
  end if;

  delete from public.shop_item_alias
   where shop_id = p_shop_id and id = p_alias_id;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'remove_shop_item_alias', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.remove_shop_item_alias(uuid, uuid, text) from public;
grant execute on function public.remove_shop_item_alias(uuid, uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- add_shop_item_barcode (returns uuid)
-- ---------------------------------------------------------------------------

drop function if exists public.add_shop_item_barcode(
  uuid, uuid, text, boolean, text
);

create or replace function public.add_shop_item_barcode(
  p_shop_id           uuid,
  p_shop_item_unit_id uuid,
  p_barcode           text,
  p_is_primary        boolean default false,
  p_symbology         text default null,
  p_client_op_id      text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_barcode text;
  v_id      uuid;
  v_cached  text;
begin
  if p_client_op_id is not null then
    select return_value into v_cached
      from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'add_shop_item_barcode'
       and created_at > pg_catalog.now() - interval '1 hour';
    if found then
      return v_cached::uuid;
    end if;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit barcodes in this shop';
  end if;

  v_barcode := nullif(pg_catalog.btrim(p_barcode), '');
  if v_barcode is null then
    raise exception 'Barcode is required';
  end if;

  if not exists (
    select 1 from public.shop_item_unit
     where shop_id = p_shop_id and id = p_shop_item_unit_id
  ) then
    raise exception 'Packaging not found in this shop';
  end if;

  if p_is_primary then
    update public.shop_item_barcode
       set is_primary = false,
           updated_at = now()
     where shop_id = p_shop_id
       and shop_item_unit_id = p_shop_item_unit_id
       and is_primary;
  end if;

  insert into public.shop_item_barcode (
    shop_id, shop_item_unit_id, barcode, symbology, is_primary, created_by
  )
  values (
    p_shop_id, p_shop_item_unit_id, v_barcode,
    nullif(pg_catalog.btrim(coalesce(p_symbology, '')), ''),
    p_is_primary, auth.uid()
  )
  on conflict (shop_id, shop_item_unit_id, barcode) do update
     set is_active = true,
         is_primary = excluded.is_primary or public.shop_item_barcode.is_primary,
         updated_at = now()
  returning id into v_id;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'add_shop_item_barcode', v_id::text)
    on conflict do nothing;
  end if;

  return v_id;
end;
$$;

revoke all on function public.add_shop_item_barcode(
  uuid, uuid, text, boolean, text, text
) from public;
grant execute on function public.add_shop_item_barcode(
  uuid, uuid, text, boolean, text, text
) to authenticated;


-- ---------------------------------------------------------------------------
-- remove_shop_item_barcode (returns void)
-- ---------------------------------------------------------------------------

drop function if exists public.remove_shop_item_barcode(uuid, uuid);

create or replace function public.remove_shop_item_barcode(
  p_shop_id      uuid,
  p_barcode_id   uuid,
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
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'remove_shop_item_barcode'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit barcodes in this shop';
  end if;

  delete from public.shop_item_barcode
   where shop_id = p_shop_id and id = p_barcode_id;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'remove_shop_item_barcode', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.remove_shop_item_barcode(uuid, uuid, text) from public;
grant execute on function public.remove_shop_item_barcode(uuid, uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- set_primary_shop_item_barcode (returns void)
-- ---------------------------------------------------------------------------

drop function if exists public.set_primary_shop_item_barcode(uuid, uuid);

create or replace function public.set_primary_shop_item_barcode(
  p_shop_id      uuid,
  p_barcode_id   uuid,
  p_client_op_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unit_id uuid;
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'set_primary_shop_item_barcode'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit barcodes in this shop';
  end if;

  select shop_item_unit_id into v_unit_id
    from public.shop_item_barcode
   where shop_id = p_shop_id and id = p_barcode_id;
  if v_unit_id is null then
    raise exception 'Barcode not found in this shop';
  end if;

  update public.shop_item_barcode
     set is_primary = false,
         updated_at = now()
   where shop_id = p_shop_id
     and shop_item_unit_id = v_unit_id
     and id <> p_barcode_id
     and is_primary;

  update public.shop_item_barcode
     set is_primary = true,
         updated_at = now()
   where shop_id = p_shop_id
     and id = p_barcode_id;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'set_primary_shop_item_barcode', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.set_primary_shop_item_barcode(uuid, uuid, text) from public;
grant execute on function public.set_primary_shop_item_barcode(uuid, uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- update_party (returns void)
-- ---------------------------------------------------------------------------

drop function if exists public.update_party(uuid, uuid, text, text);

create or replace function public.update_party(
  p_shop_id      uuid,
  p_party_id     uuid,
  p_name         text,
  p_phone        text default null,
  p_client_op_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name  text;
  v_phone text;
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'update_party'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit parties for this shop';
  end if;

  v_name := nullif(pg_catalog.btrim(p_name), '');
  if v_name is null then
    raise exception 'Party name is required';
  end if;
  v_phone := nullif(pg_catalog.btrim(coalesce(p_phone, '')), '');

  update public.party
     set name       = v_name,
         phone      = v_phone,
         updated_at = now()
   where shop_id = p_shop_id
     and id      = p_party_id;
  if not found then
    raise exception 'Party not found in this shop';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(
      shop_id, client_op_id, rpc_name, return_value
    )
    values (p_shop_id, p_client_op_id, 'update_party', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.update_party(uuid, uuid, text, text, text) from public;
grant execute on function public.update_party(uuid, uuid, text, text, text) to authenticated;
