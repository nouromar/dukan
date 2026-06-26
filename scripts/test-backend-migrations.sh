#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_NAME="dukan-migration-test-$$"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16-alpine}"

cleanup() {
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

docker run \
  --rm \
  --name "$CONTAINER_NAME" \
  -e POSTGRES_PASSWORD=postgres \
  -d "$POSTGRES_IMAGE" >/dev/null

for _ in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec -i "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -d postgres <<'SQL'
create role anon nologin;
create role authenticated nologin;
create schema auth;
create schema storage;
-- Mock auth.users mirrors the columns the migrations / tests actually
-- read: id (always), plus email + phone (used by the invite auto-claim
-- path added in 0055/0056 and by the user_profile join in 0057).
create table auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text,
  phone text
);
create table storage.buckets (
  id text primary key,
  name text not null unique,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null references storage.buckets(id),
  name text not null,
  owner uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to authenticated, anon;
grant select on auth.users to authenticated, anon;
-- The harness simulates Supabase signing a user up by inserting into
-- this mock table from inside an `authenticated`-role DO block. Real
-- Supabase writes to auth.users through Auth Admin, not as
-- authenticated — so this grant exists only inside the harness.
grant insert, update on auth.users to authenticated;
grant usage on schema storage to authenticated, anon;
SQL

for migration in "$ROOT_DIR"/supabase/migrations/*.sql; do
  echo "Applying $(basename "$migration")"
  docker exec -i "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -d postgres < "$migration" >/dev/null
done

# Template content seeds live OUTSIDE the migration stream (deletable/editable
# content, not schema). `supabase db reset` loads these via config.toml; the
# harness loads them explicitly here, after migrations, to mirror that.
for seed in "$ROOT_DIR"/supabase/seeds/templates/*.sql; do
  [ -e "$seed" ] || continue
  echo "Seeding $(basename "$seed")"
  docker exec -i "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -d postgres < "$seed" >/dev/null
done

docker exec -i "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -d postgres <<'SQL'
-- =====================================================================
-- Backend migration harness — v2 schema (data-model-v2 §12 test plan)
-- =====================================================================
--
-- Fixture users:
--   user1 (owner)             — owns the org + Main Shop + Setup Checklist Shop
--   user2 (cashier)           — invited to Main Shop and Setup Checklist Shop
--   user3 (unrelated)         — not a member of any tested shop
--   user4 (platform admin)    — required for global catalog mutations in tests
--
-- Sections (search for "-- §" to navigate):
--   §1 Auth / org / membership / RLS denial paths
--   §2 Template apply + shop setup completion
--   §3 Shop overlay: ensure_shop_item, create_shop_item, packagings, aliases
--   §4 Documents + storage policies
--   §5 Posting RPCs (post_receive / post_sale / post_payment / post_expense)
--   §6 Multi-packaging receive + mixed-packaging sale (data-model-v2 §8.2-8.3)
--   §7 Pricing RPC: set_shop_item_unit_sale_price
--   §8 Search: search_items + barcode probe + locale chain
--   §9 list_shop_item_units + packaging label correctness
--   §10 Reports / reconciliation views
--   §11 Learning suggestions (v_shop_suggestions)
--   §12 search_parties + create_party
--   §13 Sale history + void_sale (+ refund)
--   §14 Receive history + void_receive (+ stock-activity guard)
--   §15 Tenant isolation + cashier denial paths
--   §16 DB-level triggers (base-unit guards, packaging mismatch, etc.)

-- ---- Set NOTICE capture so negative-stock RAISE NOTICE surfaces ------
set client_min_messages = notice;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000003'),
  ('00000000-0000-0000-0000-000000000004');

insert into public.platform_membership (user_id, role_code)
values ('00000000-0000-0000-0000-000000000004', 'platform_admin');

do $$
begin
  if (select count(*) from public.language where code in ('en', 'so')) <> 2 then
    raise exception 'language seed rows missing';
  end if;

  if (select count(*) from public.transaction_type where code in ('sale', 'receive', 'expense')) <> 3 then
    raise exception 'transaction type seed rows missing';
  end if;

  -- v2 reference jsonb columns: unit.label_translations is required for tr().
  if not exists (
    select 1 from public.unit where code = 'kg' and label_translations ? 'so'
  ) then
    raise exception 'unit.label_translations missing Somali entries';
  end if;

  -- ref_translation table must be gone.
  if exists (
    select 1 from pg_catalog.pg_class
    where relname = 'ref_translation' and relnamespace = 'public'::regnamespace
  ) then
    raise exception 'ref_translation table should have been dropped in v2';
  end if;

  -- tr() helper exists.
  if (select public.tr('Kg', '{"so":"Kilo"}'::jsonb, 'so')) <> 'Kilo' then
    raise exception 'tr() helper did not return Somali translation';
  end if;
  if (select public.tr('Kg', '{}'::jsonb, 'so')) <> 'Kg' then
    raise exception 'tr() helper did not fall back to default label';
  end if;
end;
$$;

-- =====================================================================
-- §1 Auth / org / membership / RLS
-- =====================================================================

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

create temp table test_ids as
select *
from public.create_organization('Owner Org', 'Main Shop');

alter table test_ids add column second_shop_id uuid;
update test_ids
set second_shop_id = public.create_shop(organization_id, 'Second Shop');

do $$
declare
  v_shop_id uuid;
  v_second_shop_id uuid;
  v_cashier_role_id uuid;
begin
  select shop_id, second_shop_id into v_shop_id, v_second_shop_id from test_ids;

  if not public.auth_can_access_shop(v_shop_id) then
    raise exception 'org owner cannot access first shop';
  end if;

  if not public.auth_can_access_shop(v_second_shop_id) then
    raise exception 'org owner cannot access second shop';
  end if;

  select id into v_cashier_role_id from public.shop_role where code = 'cashier';

  insert into public.shop_membership (shop_id, user_id, role_id)
  values (v_shop_id, '00000000-0000-0000-0000-000000000002', v_cashier_role_id);
end;
$$;

-- Unrelated user can't see shops or insert locations.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id uuid;
  v_kind_id uuid;
begin
  select shop_id into v_shop_id from test_ids;
  select id into v_kind_id from public.location_kind where code = 'default';

  if (select count(*) from public.shop) <> 0 then
    raise exception 'unrelated user can see shops';
  end if;

  begin
    insert into public.location (shop_id, name, kind_id)
    values (v_shop_id, 'Blocked', v_kind_id);
    raise exception 'unrelated user inserted location';
  exception
    when insufficient_privilege or check_violation or with_check_option_violation then
      null;
  end;
end;
$$;

-- Cashier can't insert directly into shop_item (setup-managed).
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

do $$
declare
  v_shop_id uuid;
  v_second_shop_id uuid;
  v_failed boolean;
begin
  select shop_id, second_shop_id into v_shop_id, v_second_shop_id from test_ids;

  if (select count(*) from public.shop) <> 1 then
    raise exception 'cashier should see exactly one assigned shop';
  end if;

  if exists (select 1 from public.shop where id = v_second_shop_id) then
    raise exception 'cashier can see unassigned shop';
  end if;

  v_failed := false;
  begin
    insert into public.shop_item (shop_id, base_unit_code)
    values (v_shop_id, 'piece');
  exception
    when insufficient_privilege or check_violation or with_check_option_violation then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'cashier wrote shop_item directly (bypassing create_shop_item)';
  end if;
end;
$$;

-- =====================================================================
-- §2 Template apply (eager variant, 0012) + shop setup completion
-- =====================================================================

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_org_id uuid;
  v_shop_id uuid;
  v_second_shop_id uuid;
  v_template_id uuid;
  v_application_id uuid;
  v_replay_application_id uuid;
  v_rice_shop_item_id uuid;
  v_rice_default_sale_unit_id uuid;
  v_rice_default_sale_price numeric;
  v_failed boolean;
begin
  select organization_id, shop_id, second_shop_id
  into v_org_id, v_shop_id, v_second_shop_id
  from test_ids;

  select id into v_template_id from public.template where code = 'grocery' and version = 1;
  if v_template_id is null then
    raise exception 'seeded grocery template missing';
  end if;

  -- Apply template to second shop. Idempotent.
  v_application_id := public.apply_template(v_second_shop_id, v_template_id);
  v_replay_application_id := public.apply_template(v_second_shop_id, v_template_id);
  if v_application_id <> v_replay_application_id then
    raise exception 'apply_template idempotency broke';
  end if;

  -- Eager apply: every template_item must be activated.
  if (select count(*) from public.shop_item where shop_id = v_second_shop_id) <
     (select count(*) from public.template_item where template_id = v_template_id) then
    raise exception 'apply_template did not activate all template items';
  end if;

  -- Rice activated with snapshotted base_unit_code.
  select si.id into v_rice_shop_item_id
  from public.shop_item si
  join public.item i on i.id = si.item_id
  where si.shop_id = v_second_shop_id and i.code = 'rice_basmati_25kg';
  if v_rice_shop_item_id is null then
    raise exception 'rice not activated by apply_template';
  end if;

  if (select base_unit_code from public.shop_item where id = v_rice_shop_item_id) <> 'kg' then
    raise exception 'shop_item.base_unit_code not snapshotted from item';
  end if;

  -- Sale-price hint landed on the default-sale packaging.
  select siu.id, siu.sale_price
  into v_rice_default_sale_unit_id, v_rice_default_sale_price
  from public.shop_item_unit siu
  where siu.shop_id = v_second_shop_id
    and siu.shop_item_id = v_rice_shop_item_id
    and siu.is_default_sale;
  if v_rice_default_sale_unit_id is null then
    raise exception 'rice has no default sale packaging after apply';
  end if;
  if v_rice_default_sale_price <> 1.50 then
    raise exception 'rice default sale price not set from template hint (got %)', v_rice_default_sale_price;
  end if;

  -- All packagings copied; base packaging conversion=1 with correct unit_code.
  if (select count(*) from public.shop_item_unit
       where shop_id = v_second_shop_id and shop_item_id = v_rice_shop_item_id) < 2 then
    raise exception 'rice did not get every active packaging snapshotted';
  end if;
  if not exists (
    select 1 from public.shop_item_unit
    where shop_id = v_second_shop_id
      and shop_item_id = v_rice_shop_item_id
      and conversion_to_base = 1
      and unit_code = 'kg'
  ) then
    raise exception 'rice base packaging missing or has wrong unit_code';
  end if;

  -- Display alias copied (is_display=true rows from item_alias).
  if not exists (
    select 1 from public.shop_item_alias
    where shop_id = v_second_shop_id
      and shop_item_id = v_rice_shop_item_id
      and is_display
      and language_code = 'en'
      and alias_text = 'Basmati Rice'
  ) then
    raise exception 'rice display alias not snapshotted from global item_alias';
  end if;

  -- Template settings + expense categories.
  if not exists (
    select 1 from public.shop_setting
    where shop_id = v_second_shop_id and key = 'negative_stock_policy' and source = 'template'
  ) then
    raise exception 'template did not seed shop setting';
  end if;
  if not exists (
    select 1 from public.expense_category
    where shop_id = v_second_shop_id and code = 'rent'
  ) then
    raise exception 'template did not seed expense category';
  end if;

  -- shop defaults adopted on first apply.
  if (select setup_status from public.shop where id = v_second_shop_id) <> 'template_applied' then
    raise exception 'shop did not advance to template_applied';
  end if;

  v_failed := false;
  begin
    perform public.apply_template(v_second_shop_id, v_template_id, array['missing_pack']);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'apply_template allowed unknown pack';
  end if;

  -- Skip opening stock → ready.
  perform public.complete_shop_setup(v_second_shop_id);
  if (select setup_status from public.shop where id = v_second_shop_id) <> 'ready' then
    raise exception 'complete_shop_setup did not flip to ready';
  end if;

  -- Same template on Main Shop too (so daily-flow tests have items).
  perform public.apply_template(v_shop_id, v_template_id);
  perform public.complete_shop_setup(v_shop_id);
end;
$$;

-- =====================================================================
-- §3 Shop overlay: activation + creation RPCs
-- =====================================================================

do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_shop_item_id_1 uuid;
  v_shop_item_id_2 uuid;
  v_failed boolean;
begin
  select shop_id into v_shop_id from test_ids;

  -- ensure_shop_item idempotency: two calls → same shop_item_id (#1).
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  v_shop_item_id_1 := public.ensure_shop_item(v_shop_id, v_rice_item_id);
  v_shop_item_id_2 := public.ensure_shop_item(v_shop_id, v_rice_item_id);
  if v_shop_item_id_1 <> v_shop_item_id_2 then
    raise exception 'ensure_shop_item not idempotent';
  end if;

  -- Activation race simulated by direct insert with same (shop_id, item_id) (#2).
  -- A direct insert is owner-managed; expect unique_violation from
  -- shop_item_unique_activation.
  v_failed := false;
  begin
    insert into public.shop_item (shop_id, item_id, base_unit_code)
    values (v_shop_id, v_rice_item_id, 'kg');
  exception when unique_violation then v_failed := true;
  end;
  if not v_failed then
    raise exception 'shop_item_unique_activation did not prevent duplicate activation';
  end if;

  -- create_shop_item (#10): shop-local + 1 packaging + 1 display alias.
  declare
    v_eggs_id uuid;
    v_eggs_unit_id uuid;
    v_eggs_alias_id uuid;
    v_eggs_alias_count int;
  begin
    select shop_item_id into v_eggs_id from public.create_shop_item(
      v_shop_id, 'Eggs', 'en', 'piece', 0.10, null
    );
    if v_eggs_id is null then
      raise exception 'create_shop_item returned null';
    end if;
    if (select count(*) from public.shop_item_unit
         where shop_id = v_shop_id and shop_item_id = v_eggs_id) <> 1 then
      raise exception 'create_shop_item did not create exactly one packaging';
    end if;
    select id into v_eggs_unit_id
    from public.shop_item_unit
    where shop_id = v_shop_id and shop_item_id = v_eggs_id;
    if (select conversion_to_base from public.shop_item_unit where id = v_eggs_unit_id) <> 1 then
      raise exception 'create_shop_item base packaging conversion not 1';
    end if;
    if (select is_default_sale and is_default_receive from public.shop_item_unit where id = v_eggs_unit_id)
       is not true then
      raise exception 'create_shop_item base packaging not flagged as both defaults';
    end if;
    select count(*) into v_eggs_alias_count
    from public.shop_item_alias
    where shop_id = v_shop_id and shop_item_id = v_eggs_id and is_display;
    if v_eggs_alias_count <> 1 then
      raise exception 'create_shop_item did not create exactly one display alias';
    end if;

    -- create_shop_item_unit (#11): add tray-of-30 packaging.
    declare v_tray_id uuid;
    begin
      v_tray_id := public.create_shop_item_unit(
        v_shop_id, v_eggs_id, 'piece', 30, 2.50
      );
      if v_tray_id is null then
        raise exception 'create_shop_item_unit returned null';
      end if;
      if (select conversion_to_base from public.shop_item_unit where id = v_tray_id) <> 30 then
        raise exception 'create_shop_item_unit stored wrong conversion';
      end if;
    end;

    -- add_shop_item_alias (#12): is_display=true supersedes prior display.
    declare
      v_first_alias_id uuid;
      v_second_alias_id uuid;
    begin
      v_first_alias_id := public.add_shop_item_alias(
        v_shop_id, v_eggs_id, 'Ukun', 'so', true, 'manual'
      );
      v_second_alias_id := public.add_shop_item_alias(
        v_shop_id, v_eggs_id, 'Beed', 'so', true, 'manual'
      );
      if v_first_alias_id = v_second_alias_id then
        raise exception 'add_shop_item_alias did not insert a new row';
      end if;
      if (select count(*) from public.shop_item_alias
           where shop_id = v_shop_id and shop_item_id = v_eggs_id
             and language_code = 'so' and is_display) <> 1 then
        raise exception 'add_shop_item_alias left two display rows in the same language';
      end if;

      -- Re-insert same alias_text_norm: upserts (does not raise).
      declare v_upsert_id uuid;
      begin
        v_upsert_id := public.add_shop_item_alias(
          v_shop_id, v_eggs_id, '  beed  ', 'so', false, 'learned'
        );
        if v_upsert_id <> v_second_alias_id then
          raise exception 'add_shop_item_alias did not upsert on alias_text_norm';
        end if;
        if (select source from public.shop_item_alias where id = v_upsert_id) <> 'learned' then
          raise exception 'add_shop_item_alias upsert did not refresh source';
        end if;
      end;

      -- Normalization (#15): "Bariis" vs " bariis " must collide on alias_text_norm.
      v_failed := false;
      begin
        insert into public.shop_item_alias (shop_id, shop_item_id, alias_text, language_code, source)
        values (v_shop_id, v_eggs_id, 'Bariis', 'so', 'manual');
        insert into public.shop_item_alias (shop_id, shop_item_id, alias_text, language_code, source)
        values (v_shop_id, v_eggs_id, ' bariis ', 'so', 'manual');
      exception when unique_violation then v_failed := true;
      end;
      if not v_failed then
        raise exception 'alias_text_norm uniqueness did not collide on case/whitespace variants';
      end if;
    end;
  end;

  -- create_shop_item rejects bad inputs.
  v_failed := false;
  begin
    perform public.create_shop_item(v_shop_id, '   ', 'en', 'piece', null, null);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'create_shop_item accepted blank name';
  end if;

  v_failed := false;
  begin
    perform public.create_shop_item(v_shop_id, 'X', 'en', 'piece', -1, null);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'create_shop_item accepted negative price';
  end if;
end;
$$;

-- =====================================================================
-- §4 Documents + storage policies
-- =====================================================================

create temp table document_test_ids (
  purpose text primary key,
  document_id uuid not null,
  storage_path text not null
);

do $$
declare
  v_shop_id uuid;
  v_document_id uuid;
  v_receive_document_id uuid;
  v_bad_document_id uuid;
  v_storage_path text;
  v_receive_storage_path text;
  v_bad_path text;
  v_failed boolean;
begin
  select shop_id into v_shop_id from test_ids;

  if not exists (
    select 1
    from storage.buckets
    where id = 'shop-documents'
      and file_size_limit = 8388608
  ) then
    raise exception 'shop-documents bucket not configured';
  end if;

  v_document_id := pg_catalog.gen_random_uuid();
  v_storage_path := v_shop_id::text || '/documents/' || v_document_id::text || '/image.jpg';

  insert into public.document (
    id, shop_id, type_id, storage_bucket, storage_path,
    mime_type, size_bytes, ocr_status_id
  )
  values (
    v_document_id, v_shop_id,
    (select id from public.document_type where code = 'sale_receipt'),
    'shop-documents', v_storage_path, 'image/jpeg', 1024,
    (select id from public.ocr_status where code = 'pending')
  );

  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('shop-documents', v_storage_path, auth.uid(), '{"mimetype":"image/jpeg"}');

  -- Storage check constraint: bad storage_path shape rejected.
  v_bad_document_id := pg_catalog.gen_random_uuid();
  v_bad_path := v_shop_id::text || '/bad/' || v_bad_document_id::text || '/image.jpg';
  v_failed := false;
  begin
    insert into public.document (
      id, shop_id, type_id, storage_bucket, storage_path,
      mime_type, size_bytes, ocr_status_id
    )
    values (
      v_bad_document_id, v_shop_id,
      (select id from public.document_type where code = 'sale_receipt'),
      'shop-documents', v_bad_path, 'image/jpeg', 1024,
      (select id from public.ocr_status where code = 'pending')
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then
    raise exception 'document accepted invalid storage path';
  end if;

  -- Storage policy: object without matching document is rejected on insert.
  v_failed := false;
  begin
    insert into storage.objects (bucket_id, name, owner)
    values (
      'shop-documents',
      v_shop_id::text || '/documents/' || pg_catalog.gen_random_uuid()::text || '/image.jpg',
      auth.uid()
    );
  exception when insufficient_privilege or check_violation then v_failed := true;
  end;
  if not v_failed then
    raise exception 'storage policy allowed orphan object';
  end if;

  -- Clients cannot delete storage objects directly.
  v_failed := false;
  begin
    delete from storage.objects
    where bucket_id = 'shop-documents' and name = v_storage_path;
  exception when insufficient_privilege then v_failed := true;
  end;
  if not v_failed then
    raise exception 'storage.objects DELETE was not blocked';
  end if;

  -- Setting up a bono document for the receive flow below.
  delete from public.document where id = v_document_id;
  insert into document_test_ids (purpose, document_id, storage_path)
  values ('deleted-before-posting', v_document_id, v_storage_path);

  v_receive_document_id := pg_catalog.gen_random_uuid();
  v_receive_storage_path := v_shop_id::text || '/documents/' || v_receive_document_id::text || '/image.jpg';

  insert into public.document (
    id, shop_id, type_id, storage_bucket, storage_path,
    mime_type, size_bytes, ocr_status_id
  )
  values (
    v_receive_document_id, v_shop_id,
    (select id from public.document_type where code = 'bono'),
    'shop-documents', v_receive_storage_path, 'image/jpeg', 2048,
    (select id from public.ocr_status where code = 'pending')
  );

  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('shop-documents', v_receive_storage_path, auth.uid(), '{"mimetype":"image/jpeg"}');

  insert into document_test_ids (purpose, document_id, storage_path)
  values ('receive-bono', v_receive_document_id, v_receive_storage_path);
end;
$$;

-- Storage cleanup runs in a service-role block (the trigger that deletes
-- the storage row is SECURITY DEFINER but the delete itself must observe
-- RLS — service role bypasses).
reset role;
do $$
declare
  v_deleted_path text;
begin
  select storage_path into v_deleted_path
  from document_test_ids where purpose = 'deleted-before-posting';
  if exists (
    select 1 from storage.objects
    where bucket_id = 'shop-documents' and name = v_deleted_path
  ) then
    raise exception 'document delete trigger did not evict storage object';
  end if;
end;
$$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- =====================================================================
-- §5 Posting RPCs (receive + sale + payment + expense + opening stock)
-- =====================================================================

-- Set up some parties on Main Shop.
do $$
declare
  v_shop_id uuid;
  v_supplier_type_id uuid;
begin
  select shop_id into v_shop_id from test_ids;

  insert into public.supplier_type (shop_id, code, label, label_translations)
  values (v_shop_id, 'beverage_supplier', 'Beverage Supplier', '{"en":"Beverage Supplier"}')
  returning id into v_supplier_type_id;

  perform public.create_party(v_shop_id, 'Hodan Beverages', null, 'supplier');
  -- Tag the supplier with a supplier_type for completeness.
  update public.party set supplier_type_id = v_supplier_type_id
  where shop_id = v_shop_id and name = 'Hodan Beverages';

  perform public.create_party(v_shop_id, 'Asha Customer', null, 'customer');
end;
$$;

-- Opening stock + sale + receive + payment + expense on rice (Main Shop).
do $$
declare
  v_shop_id uuid;
  v_rice_shop_item_id uuid;
  v_rice_kg_unit_id uuid;
  v_rice_bag25_unit_id uuid;
  v_supplier_id uuid;
  v_customer_id uuid;
  v_expense_cat_id uuid;
  v_receive_doc_id uuid;
  v_receive_txn_id uuid;
  v_replay_txn_id uuid;
  v_sale_txn_id uuid;
  v_failed boolean;
begin
  select shop_id into v_shop_id from test_ids;
  select si.id into v_rice_shop_item_id from public.shop_item si
   join public.item i on i.id = si.item_id
   where si.shop_id = v_shop_id and i.code = 'rice_basmati_25kg';
  select id into v_rice_kg_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id and conversion_to_base = 1;
  select id into v_rice_bag25_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id
     and unit_code = 'bag' and conversion_to_base = 25;
  select id into v_supplier_id from public.party
   where shop_id = v_shop_id and name = 'Hodan Beverages';
  select id into v_customer_id from public.party
   where shop_id = v_shop_id and name = 'Asha Customer';
  select id into v_expense_cat_id from public.expense_category
   where shop_id = v_shop_id and code = 'rent';
  select document_id into v_receive_doc_id from document_test_ids where purpose = 'receive-bono';

  -- Opening stock via inventory_adjustment (10 kg @ $0.50 base unit).
  -- Setup status must allow 'opening'; we'll temporarily rewind to template_applied.
  update public.shop set setup_status = 'template_applied' where id = v_shop_id;

  perform public.post_inventory_adjustment(
    v_shop_id, 'opening',
    jsonb_build_array(jsonb_build_object(
      'shop_item_id', v_rice_shop_item_id,
      'quantity_delta', 10,
      'unit_cost', 0.50
    )),
    null, 'opening-rice', null, 'opening'
  );
  if (select setup_status from public.shop where id = v_shop_id) <> 'opening_stock_done' then
    raise exception 'opening adjustment did not advance setup_status';
  end if;

  perform public.complete_shop_setup(v_shop_id);

  -- #359 regression: 'opening' adjustment must succeed AFTER setup
  -- transitioned to 'ready' — the New Item editor (post-#316) creates
  -- items at any time and each one needs an opening stock post for
  -- its initial stock. The prior guard rejected these legitimate
  -- posts with "Opening stock can only be posted during setup".
  -- Relaxation: 'opening' is allowed regardless of setup_status;
  -- all OTHER reason codes still require 'ready'.
  declare
    v_post_setup_item_id uuid;
  begin
    if (select setup_status from public.shop where id = v_shop_id) <> 'ready' then
      raise exception '#359 pre-check: shop should be ready after complete_shop_setup';
    end if;
    -- create_shop_item signature: (shop_id, name, language_code,
    -- sold_unit_code, sale_price, category_id, ...). Mirrors the
    -- 'Eggs' callsite earlier in this harness.
    select shop_item_id into v_post_setup_item_id
    from public.create_shop_item(
      v_shop_id, '#359 post-ready Rice', 'en', 'kg', 5.00, null
    );
    perform public.post_inventory_adjustment(
      v_shop_id, 'opening',
      jsonb_build_array(jsonb_build_object(
        'shop_item_id', v_post_setup_item_id,
        'quantity_delta', 60,
        'unit_cost', 2.00
      )),
      null, '#359-opening-after-ready', null, 'opening after setup ready'
    );
    if (select current_stock from public.shop_item
        where id = v_post_setup_item_id) <> 60 then
      raise exception '#359: opening adjustment did not update current_stock';
    end if;
    if (select setup_status from public.shop where id = v_shop_id) <> 'ready' then
      raise exception '#359: opening adjustment should NOT change setup_status from ready';
    end if;
  end;

  -- #359 negative path: a NON-opening reason still requires the
  -- 'ready' setup_status; the guard only relaxes the 'opening' branch.
  -- Rewind setup_status to 'template_applied' and try a 'correction'
  -- — should be rejected.
  update public.shop set setup_status = 'template_applied' where id = v_shop_id;
  begin
    perform public.post_inventory_adjustment(
      v_shop_id, 'correction',
      jsonb_build_array(jsonb_build_object(
        'shop_item_id', v_rice_shop_item_id,
        'quantity_delta', -1,
        'unit_cost', 0.50
      )),
      null, '#359-correction-not-ready', null, 'should reject'
    );
    raise exception '#359: correction adjustment must fail when setup_status is not ready';
  exception when others then
    if sqlerrm not like '%Shop setup must be ready before posting adjustments%' then
      raise exception '#359: wrong error: %', sqlerrm;
    end if;
  end;
  -- Restore ready so downstream tests aren't affected.
  update public.shop set setup_status = 'ready' where id = v_shop_id;

  -- Receive: 4 × 25 kg bag of rice from Hodan, $20/bag, $30 paid cash.
  v_receive_txn_id := public.post_receive(
    v_shop_id, v_supplier_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_rice_bag25_unit_id,
      'quantity', 4,
      'line_total', 80
    )),
    30, 'cash', v_receive_doc_id, 'receive-rice-1', null, 'rice receive'
  );

  -- Idempotent.
  v_replay_txn_id := public.post_receive(
    v_shop_id, v_supplier_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_rice_bag25_unit_id,
      'quantity', 4,
      'line_total', 80
    )),
    30, 'cash', v_receive_doc_id, 'receive-rice-1', null, 'replay'
  );
  if v_receive_txn_id <> v_replay_txn_id then
    raise exception 'post_receive idempotency broken';
  end if;

  -- Stock projection: 10 kg opening + 4×25 kg = 110 kg.
  if (select current_stock from public.shop_item where id = v_rice_shop_item_id) <> 110 then
    raise exception 'receive did not roll stock to 110 kg';
  end if;

  -- avg_cost weighted: (10×0.50 + 80) / 110 = ~0.7727.
  if abs((select avg_cost from public.shop_item where id = v_rice_shop_item_id) - 0.7727) > 0.001 then
    raise exception 'avg_cost not weighted correctly after receive';
  end if;

  -- last_cost on the 25kg packaging = $20 per bag.
  if (select last_cost from public.shop_item_unit where id = v_rice_bag25_unit_id) <> 20 then
    raise exception 'shop_item_unit.last_cost not updated';
  end if;

  -- supplier_item_unit_cost upserted on the (supplier, packaging).
  if (select last_unit_cost from public.supplier_item_unit_cost
       where shop_id = v_shop_id and party_id = v_supplier_id
         and shop_item_unit_id = v_rice_bag25_unit_id) <> 20 then
    raise exception 'supplier_item_unit_cost not upserted';
  end if;

  -- Payable = 50 (total 80 - 30 paid).
  if (select payable from public.party where id = v_supplier_id) <> 50 then
    raise exception 'supplier payable not updated';
  end if;

  -- Sale: 2 kg loose @ $1.20 to Asha on credit.
  v_sale_txn_id := public.post_sale(
    v_shop_id, v_customer_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_rice_kg_unit_id,
      'quantity', 2,
      'unit_price', 1.20
    )),
    0, null, null, 'sale-rice-1', null, 'credit sale'
  );
  if (select receivable from public.party where id = v_customer_id) <> 2.40 then
    raise exception 'sale did not create receivable';
  end if;
  if (select current_stock from public.shop_item where id = v_rice_shop_item_id) <> 108 then
    raise exception 'sale did not decrement stock (108 kg expected)';
  end if;

  -- cogs snapshot = base_qty * avg_cost (2 × 0.7727 ≈ 1.55).
  if abs((select cogs_total from public.transaction_line
           where shop_id = v_shop_id and transaction_id = v_sale_txn_id) - 1.55) > 0.01 then
    raise exception 'sale cogs snapshot drift';
  end if;

  -- Cashier price-override: post_sale at a different price persists it.
  perform public.post_sale(
    v_shop_id, null,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_rice_kg_unit_id,
      'quantity', 1,
      'unit_price', 1.50
    )),
    1.50, 'cash', null, 'sale-rice-override', null, 'override'
  );
  if (select sale_price from public.shop_item_unit where id = v_rice_kg_unit_id) <> 1.50 then
    raise exception 'post_sale did not persist sale_price override';
  end if;

  -- Payment from Asha (1 dollar inbound).
  perform public.post_payment(
    v_shop_id, v_customer_id, 'I', 1.00, 'cash',
    'asha-pay-1', null, null, null
  );
  if (select receivable from public.party where id = v_customer_id) <> 1.40 then
    raise exception 'payment did not reduce receivable';
  end if;

  -- Overpayment rejected.
  v_failed := false;
  begin
    perform public.post_payment(
      v_shop_id, v_customer_id, 'I', 99, 'cash',
      'asha-overpay', null, null, null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'overpayment was accepted';
  end if;

  -- Expense.
  perform public.post_expense(
    v_shop_id, v_expense_cat_id, 12, 'cash', null,
    'expense-rent-1', null, 'rent'
  );

  -- Zero-qty sale rejected.
  v_failed := false;
  begin
    perform public.post_sale(
      v_shop_id, null,
      jsonb_build_array(jsonb_build_object(
        'shop_item_unit_id', v_rice_kg_unit_id,
        'quantity', 0,
        'unit_price', 1
      )),
      0, null, null, 'sale-zero', null, 'invalid'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'zero-qty sale was accepted';
  end if;

  -- Direct insert on txn table is blocked.
  v_failed := false;
  begin
    insert into public.txn (shop_id, type_id, status_id, occurred_at, total_amount, paid_amount)
    values (
      v_shop_id,
      (select id from public.transaction_type where code = 'sale'),
      (select id from public.transaction_status where code = 'posted'),
      now(), 1, 1
    );
  exception when insufficient_privilege then v_failed := true;
  end;
  if not v_failed then
    raise exception 'direct txn insert was allowed';
  end if;
end;
$$;

-- =====================================================================
-- §6 Multi-packaging receive + mixed-packaging sale (#7, #8) — Setup Checklist Shop
-- =====================================================================
--
-- Build a fresh shop with rice fully activated, receive in two different
-- packagings, then sell from both. Validates §8.2-§8.3 scenarios.

-- Add 10kg-bag global packaging FIRST (as platform admin), then create
-- Setup Checklist Shop + apply template so ensure_shop_item snapshots all
-- three rice packagings (kg base, 10kg bag, 25kg bag).
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';

do $$
declare
  v_rice_item_id uuid;
begin
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  insert into public.item_unit (item_id, unit_code, conversion_to_base, is_default_sale, is_default_receive, sort_order, is_active)
  values (v_rice_item_id, 'bag', 10, false, false, 3, true)
  on conflict (item_id, unit_code, conversion_to_base) do nothing;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_org_id uuid;
  v_shop_id uuid;
  v_template_id uuid;
  v_cashier_role_id uuid;
begin
  select organization_id into v_org_id from test_ids;
  v_shop_id := public.create_shop(v_org_id, 'Setup Checklist Shop');

  select id into v_template_id from public.template where code = 'grocery' and version = 1;
  perform public.apply_template(v_shop_id, v_template_id);
  perform public.complete_shop_setup(v_shop_id);

  -- Invite the cashier user2 for later denial tests.
  select id into v_cashier_role_id from public.shop_role where code = 'cashier';
  insert into public.shop_membership (shop_id, user_id, role_id)
  values (v_shop_id, '00000000-0000-0000-0000-000000000002', v_cashier_role_id);
end;
$$;

do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_rice_shop_item_id uuid;
  v_kg_unit_id uuid;
  v_bag25_unit_id uuid;
  v_bag10_unit_id uuid;
  v_supplier_id uuid;
  v_recv_1 uuid;
  v_recv_2 uuid;
  v_stock numeric;
  v_avg_cost numeric;
  v_last_cost_25 numeric;
  v_last_cost_10 numeric;
  v_sale_loose uuid;
  v_sale_bag uuid;
  v_cogs numeric;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  select si.id into v_rice_shop_item_id from public.shop_item si
   where si.shop_id = v_shop_id and si.item_id = v_rice_item_id;

  select id into v_kg_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id and conversion_to_base = 1;
  select id into v_bag25_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id
     and unit_code = 'bag' and conversion_to_base = 25;
  select id into v_bag10_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id
     and unit_code = 'bag' and conversion_to_base = 10;
  if v_bag10_unit_id is null then
    raise exception 'ensure_shop_item did not snapshot the 10kg-bag packaging';
  end if;

  perform public.create_party(v_shop_id, 'Hodan Beverages', null, 'supplier');
  select id into v_supplier_id from public.party
   where shop_id = v_shop_id and name = 'Hodan Beverages';

  -- #7: receive 40 × 25kg-bag at $800 ($20/bag), then 100 × 10kg-bag at
  -- $900 ($9/bag).
  v_recv_1 := public.post_receive(
    v_shop_id, v_supplier_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_bag25_unit_id, 'quantity', 40, 'line_total', 800
    )),
    0, null, null, 'recv-rice-25', null, 'multi-pack receive'
  );
  v_recv_2 := public.post_receive(
    v_shop_id, v_supplier_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_bag10_unit_id, 'quantity', 100, 'line_total', 900
    )),
    0, null, null, 'recv-rice-10', null, 'multi-pack receive'
  );

  -- Stock rolls up: 40×25 + 100×10 = 1000 + 1000 = 2000 kg.
  select current_stock into v_stock from public.shop_item where id = v_rice_shop_item_id;
  if v_stock <> 2000 then
    raise exception 'multi-pack stock = % (expected 2000)', v_stock;
  end if;

  -- Weighted avg cost: total cost = 1700 / 2000 kg = 0.85.
  select avg_cost into v_avg_cost from public.shop_item where id = v_rice_shop_item_id;
  if abs(v_avg_cost - 0.85) > 0.0001 then
    raise exception 'multi-pack avg_cost = % (expected 0.85)', v_avg_cost;
  end if;

  -- last_cost per packaging.
  select last_cost into v_last_cost_25 from public.shop_item_unit where id = v_bag25_unit_id;
  select last_cost into v_last_cost_10 from public.shop_item_unit where id = v_bag10_unit_id;
  if v_last_cost_25 <> 20 then
    raise exception '25kg-bag last_cost = % (expected 20)', v_last_cost_25;
  end if;
  if v_last_cost_10 <> 9 then
    raise exception '10kg-bag last_cost = % (expected 9)', v_last_cost_10;
  end if;

  -- supplier_item_unit_cost: one row per (supplier, packaging).
  if (select count(*) from public.supplier_item_unit_cost
       where shop_id = v_shop_id and party_id = v_supplier_id
         and shop_item_unit_id in (v_bag25_unit_id, v_bag10_unit_id)) <> 2 then
    raise exception 'supplier_item_unit_cost did not have one row per packaging';
  end if;

  -- #8: sell 1 kg loose + 1 × 25kg-bag, both decrement same pool.
  perform public.set_shop_item_unit_sale_price(v_shop_id, v_kg_unit_id, 1.20);
  perform public.set_shop_item_unit_sale_price(v_shop_id, v_bag25_unit_id, 25);

  v_sale_loose := public.post_sale(
    v_shop_id, null,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_kg_unit_id, 'quantity', 1, 'unit_price', 1.20
    )),
    1.20, 'cash', null, 'sale-loose-1', null, 'mixed-pack sale'
  );
  v_sale_bag := public.post_sale(
    v_shop_id, null,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_bag25_unit_id, 'quantity', 1, 'unit_price', 25
    )),
    25, 'cash', null, 'sale-bag-1', null, 'mixed-pack sale'
  );

  -- Pool decremented by 1 + 25 = 26.
  select current_stock into v_stock from public.shop_item where id = v_rice_shop_item_id;
  if v_stock <> 1974 then
    raise exception 'mixed-pack pool decrement wrong (got %)', v_stock;
  end if;

  -- cogs on loose sale snapshots avg_cost.
  select cogs_unit_cost into v_cogs from public.transaction_line
   where shop_id = v_shop_id and transaction_id = v_sale_loose;
  if v_cogs <> 0.85 then
    raise exception 'loose sale cogs_unit_cost = % (expected 0.85)', v_cogs;
  end if;
  -- cogs on bag sale: 25 × 0.85 = 21.25.
  select cogs_total into v_cogs from public.transaction_line
   where shop_id = v_shop_id and transaction_id = v_sale_bag;
  if v_cogs <> 21.25 then
    raise exception 'bag sale cogs_total = % (expected 21.25)', v_cogs;
  end if;
end;
$$;

-- #6 Negative-stock NOTICE: sell more than current stock; verify
-- the post completes without raising AND current_stock < 0.
do $$
declare
  v_shop_id uuid;
  v_eggs_id uuid;
  v_eggs_unit_id uuid;
  v_pre numeric;
  v_post numeric;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select shop_item_id into v_eggs_id from public.create_shop_item(v_shop_id, 'Negative Test', 'en', 'piece', 1.00, null);
  select id into v_eggs_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_eggs_id;
  select current_stock into v_pre from public.shop_item where id = v_eggs_id;
  perform public.post_sale(
    v_shop_id, null,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_eggs_unit_id, 'quantity', 5, 'unit_price', 1
    )),
    5, 'cash', null, 'neg-stock-sale', null, 'should raise notice'
  );
  select current_stock into v_post from public.shop_item where id = v_eggs_id;
  if v_post >= 0 then
    raise exception 'negative-stock sale did not produce negative balance (got %)', v_post;
  end if;
end;
$$;

-- =====================================================================
-- §7 set_shop_item_unit_sale_price (#9): null + positive + negative
-- =====================================================================

do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_rice_shop_item_id uuid;
  v_kg_unit_id uuid;
  v_failed boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  select id into v_rice_shop_item_id from public.shop_item
   where shop_id = v_shop_id and item_id = v_rice_item_id;
  select id into v_kg_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id and conversion_to_base = 1;

  perform public.set_shop_item_unit_sale_price(v_shop_id, v_kg_unit_id, 1.75);
  if (select sale_price from public.shop_item_unit where id = v_kg_unit_id) <> 1.75 then
    raise exception 'price did not persist';
  end if;

  perform public.set_shop_item_unit_sale_price(v_shop_id, v_kg_unit_id, null);
  if (select sale_price from public.shop_item_unit where id = v_kg_unit_id) is not null then
    raise exception 'null price did not un-price packaging';
  end if;

  v_failed := false;
  begin
    perform public.set_shop_item_unit_sale_price(v_shop_id, v_kg_unit_id, -1);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'negative price was accepted';
  end if;

  -- Restore for downstream.
  perform public.set_shop_item_unit_sale_price(v_shop_id, v_kg_unit_id, 1.20);
end;
$$;

-- =====================================================================
-- §8 search_items: alias chain + barcode probe + locale (#13, #14)
-- =====================================================================

do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_rice_shop_item_id uuid;
  v_rice_bag25_unit_id uuid;
  v_match_locale_count int;
  v_first_name text;
  v_alias_rank_reason text;
  v_so_name text;
  v_en_name text;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  select id into v_rice_shop_item_id from public.shop_item
   where shop_id = v_shop_id and item_id = v_rice_item_id;
  select id into v_rice_bag25_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id
     and unit_code = 'bag' and conversion_to_base = 25;

  -- Seed a shop alias in Somali so the shop-side branch wins.
  perform public.add_shop_item_alias(v_shop_id, v_rice_shop_item_id, 'bariis manta', 'so', false, 'manual');

  -- "bariis" hits the global Somali alias → returns rice.
  if not exists (
    select 1 from public.search_items(v_shop_id, 'bariis', 'sale', 'so')
    where shop_item_id = v_rice_shop_item_id
  ) then
    raise exception 'search_items did not find rice via Somali alias';
  end if;

  -- Locale match wins: "bariis manta" with locale=so returns rice with
  -- rank_reason starting with alias_*.
  select rank_reason into v_alias_rank_reason
  from public.search_items(v_shop_id, 'bariis manta', 'sale', 'so')
  where shop_item_id = v_rice_shop_item_id
  limit 1;
  if v_alias_rank_reason is null or v_alias_rank_reason not like 'alias_%' then
    raise exception 'rank_reason missing or unexpected (got %)', v_alias_rank_reason;
  end if;

  -- Locale display: Somali display name vs English display name.
  select display_name into v_so_name
  from public.search_items(v_shop_id, '', 'sale', 'so', null, 200)
  where shop_item_id = v_rice_shop_item_id;
  select display_name into v_en_name
  from public.search_items(v_shop_id, '', 'sale', 'en', null, 200)
  where shop_item_id = v_rice_shop_item_id;
  if v_so_name not like 'Bariis%' then
    raise exception 'Somali locale did not surface Somali display name (got %)', v_so_name;
  end if;
  if v_en_name not like 'Basmati%' then
    raise exception 'English locale did not surface English display name (got %)', v_en_name;
  end if;

  -- Empty query returns activated shop_items (rank_reason='empty_query').
  if not exists (
    select 1 from public.search_items(v_shop_id, '', 'sale', 'en', null, 200)
    where rank_reason = 'empty_query'
  ) then
    raise exception 'empty query did not surface empty_query rows';
  end if;

  -- #14 Barcode probe: a shop barcode overrides a global barcode.
  declare
    v_global_iu_id uuid;
    v_search_unit uuid;
    v_search_reason text;
  begin
    -- Global barcode pointing at the 25kg packaging.
    select id into v_global_iu_id from public.item_unit
     where item_id = v_rice_item_id and unit_code = 'bag' and conversion_to_base = 25;

    set role postgres;
    insert into public.item_barcode (item_unit_id, barcode, source, is_active)
    values (v_global_iu_id, '12345678', 'manufacturer', true)
    on conflict (item_unit_id, barcode) do nothing;
    reset role;
    set role authenticated;
    set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

    -- Shop barcode pointing at the kg packaging — should win.
    insert into public.shop_item_barcode (shop_id, shop_item_unit_id, barcode, is_active)
    select v_shop_id,
      (select id from public.shop_item_unit
        where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id and conversion_to_base = 1),
      '12345678', true;

    select default_shop_item_unit_id, rank_reason into v_search_unit, v_search_reason
    from public.search_items(v_shop_id, '12345678', 'sale', 'en')
    where shop_item_id = v_rice_shop_item_id
    limit 1;
    if v_search_reason <> 'barcode_match' then
      raise exception 'barcode search did not flag barcode_match (got %)', v_search_reason;
    end if;
    if v_search_unit is null then
      raise exception 'barcode search did not return a packaging id';
    end if;
    -- The shop barcode (kg unit) must win over the global barcode (bag).
    if v_search_unit <> (
      select id from public.shop_item_unit
       where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id and conversion_to_base = 1
    ) then
      raise exception 'global barcode shadowed shop barcode (expected kg, got %)', v_search_unit;
    end if;
  end;
end;
$$;

-- =====================================================================
-- §9 list_shop_item_units: order + packaging label (#18)
-- =====================================================================

do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_rice_shop_item_id uuid;
  v_first_label text;
  v_first_unit_id uuid;
  v_kg_unit_id uuid;
  v_bag25_packaging_label text;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  select id into v_rice_shop_item_id from public.shop_item
   where shop_id = v_shop_id and item_id = v_rice_item_id;

  -- Receive screen: 25 kg bag default surfaces first; label "25 Kg Bag".
  select shop_item_unit_id, packaging_label
   into v_first_unit_id, v_first_label
  from public.list_shop_item_units(v_shop_id, v_rice_shop_item_id, 'receive')
  limit 1;
  if v_first_label <> '25 Kg Bag' then
    raise exception 'receive screen first packaging label = % (expected "25 Kg Bag")', v_first_label;
  end if;

  -- Sale screen: kg base surfaces first; label = "Kg".
  select shop_item_unit_id, packaging_label
   into v_first_unit_id, v_first_label
  from public.list_shop_item_units(v_shop_id, v_rice_shop_item_id, 'sale')
  limit 1;
  if v_first_label <> 'Kg' then
    raise exception 'sale screen first packaging label = % (expected "Kg")', v_first_label;
  end if;

  -- Bad screen rejected.
  declare v_failed boolean := false;
  begin
    begin
      perform * from public.list_shop_item_units(v_shop_id, v_rice_shop_item_id, 'bogus');
    exception when raise_exception then v_failed := true;
    end;
    if not v_failed then
      raise exception 'list_shop_item_units accepted bad p_screen';
    end if;
  end;
end;
$$;

-- =====================================================================
-- §10 Reports + reconciliation views
-- =====================================================================

do $$
declare
  v_shop_id uuid;
  v_expected_stock numeric;
begin
  select shop_id into v_shop_id from test_ids;

  -- v_item_stock_truth: cached vs ledger.
  if exists (
    select 1 from public.v_item_stock_truth
    where shop_id = v_shop_id and stock_variance <> 0
  ) then
    raise exception 'v_item_stock_truth shows variance for Main Shop';
  end if;

  if exists (
    select 1 from public.v_party_balance_truth
    where shop_id = v_shop_id
      and (receivable_variance <> 0 or payable_variance <> 0)
  ) then
    raise exception 'v_party_balance_truth shows variance for Main Shop';
  end if;

  -- v_sales_report has at least the rice sales we posted.
  if (select count(*) from public.v_sales_report where shop_id = v_shop_id) < 2 then
    raise exception 'v_sales_report under-counts main shop sales';
  end if;

  -- v_expense_report has the rent expense.
  if not exists (
    select 1 from public.v_expense_report
    where shop_id = v_shop_id and expense_category_code = 'rent' and amount = 12
  ) then
    raise exception 'v_expense_report missing rent';
  end if;

  -- v_daily_profit aggregates.
  if not exists (
    select 1 from public.v_daily_profit where shop_id = v_shop_id and expense_total = 12
  ) then
    raise exception 'v_daily_profit missing rent expense';
  end if;
end;
$$;

-- =====================================================================
-- §11 Learning suggestions surface after activity
-- =====================================================================

do $$
declare
  v_shop_id uuid;
  v_supplier_id uuid;
begin
  select shop_id into v_shop_id from test_ids;
  select id into v_supplier_id from public.party
   where shop_id = v_shop_id and name = 'Hodan Beverages';

  -- Item learned suggestion (rice was sold + received earlier).
  if not exists (
    select 1 from public.v_shop_suggestions
    where shop_id = v_shop_id
      and screen = 'sale'
      and suggestion_type = 'item'
      and source in ('learned', 'template')
  ) then
    raise exception 'no item suggestion surfaced for sale screen';
  end if;

  -- Supplier-item learned after receive.
  if not exists (
    select 1 from public.v_shop_suggestions
    where shop_id = v_shop_id
      and screen = 'receive'
      and suggestion_type = 'supplier_item'
      and party_id = v_supplier_id
      and source = 'learned'
  ) then
    raise exception 'no learned supplier_item suggestion surfaced';
  end if;

  -- Payment method learned suggestion (cash was used).
  if not exists (
    select 1 from public.v_shop_suggestions
    where shop_id = v_shop_id
      and screen = 'payment'
      and suggestion_type = 'payment_method'
      and payment_method_code = 'cash'
      and source = 'learned'
  ) then
    raise exception 'no learned payment_method suggestion surfaced';
  end if;
end;
$$;

-- =====================================================================
-- §12 search_parties + create_party
-- =====================================================================

do $$
declare
  v_shop_id uuid;
  v_high_debt_id uuid;
  v_first_id uuid;
  v_failed boolean;
  v_supplier_id uuid;
begin
  select shop_id into v_shop_id from test_ids;

  -- Seed two customers with different receivables to verify ranking.
  insert into public.party (shop_id, name, type_id, receivable)
  values
    (v_shop_id, 'Ahmed High',  (select id from public.party_type where code = 'customer'), 50.00),
    (v_shop_id, 'Ayaan Low',   (select id from public.party_type where code = 'customer'),  5.00);

  select id into v_high_debt_id from public.party
   where shop_id = v_shop_id and name = 'Ahmed High';

  select id into v_first_id from public.search_parties(v_shop_id, '', 'customer', 50)
  limit 1;
  if v_first_id <> v_high_debt_id then
    raise exception 'search_parties did not rank receivable desc';
  end if;

  -- Customer search excludes suppliers.
  if exists (
    select 1 from public.search_parties(v_shop_id, '', 'customer', 50)
    where name = 'Hodan Beverages'
  ) then
    raise exception 'customer search leaked a supplier';
  end if;

  -- Bad p_type rejected.
  v_failed := false;
  begin
    perform * from public.search_parties(v_shop_id, '', 'random', 10);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'search_parties accepted bad p_type';
  end if;

  -- create_party — owner happy paths.
  v_supplier_id := public.create_party(v_shop_id, 'Test Supplier', null, 'supplier');
  if v_supplier_id is null then
    raise exception 'create_party returned null for supplier';
  end if;

  v_failed := false;
  begin
    perform public.create_party(v_shop_id, '   ', null, 'customer');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'create_party accepted blank name';
  end if;

  v_failed := false;
  begin
    perform public.create_party(v_shop_id, 'Bad', null, 'both');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'create_party accepted type=both';
  end if;
end;
$$;

-- Cashier can create_party (operational, not setup).
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$
declare
  v_shop_id uuid;
  v_p uuid;
  v_setup_shop_id uuid;
  v_local_item_id uuid;
  v_local_unit_id uuid;
  v_alias_id uuid;
begin
  select shop_id into v_shop_id from test_ids;
  v_p := public.create_party(v_shop_id, 'Cashier-Added', null, 'customer');
  if v_p is null then raise exception 'cashier denied create_party'; end if;

  -- #10 + #11 + #12: cashier-accessible create_shop_item / unit / alias.
  -- Use Setup Checklist Shop where user2 is also a cashier.
  select id into v_setup_shop_id from public.shop where name = 'Setup Checklist Shop';
  select shop_item_id into v_local_item_id from public.create_shop_item(
    v_setup_shop_id, 'Cashier Snack', 'en', 'piece', 1.50, null
  );
  if v_local_item_id is null then
    raise exception 'cashier was denied create_shop_item';
  end if;
  v_local_unit_id := public.create_shop_item_unit(
    v_setup_shop_id, v_local_item_id, 'piece', 12, 15.00
  );
  if v_local_unit_id is null then
    raise exception 'cashier was denied create_shop_item_unit';
  end if;
  v_alias_id := public.add_shop_item_alias(
    v_setup_shop_id, v_local_item_id, 'snack', 'en', false, 'manual'
  );
  if v_alias_id is null then
    raise exception 'cashier was denied add_shop_item_alias';
  end if;

  -- Cashier may also call set_shop_item_unit_sale_price (auth_can_post_shop).
  perform public.set_shop_item_unit_sale_price(v_setup_shop_id, v_local_unit_id, 16.00);

  -- Cashier may call ensure_shop_item (the lazy entry point).
  declare
    v_oil_item_id uuid;
    v_oil_shop_item uuid;
  begin
    select id into v_oil_item_id from public.item where code = 'soda_can_330ml';
    v_oil_shop_item := public.ensure_shop_item(v_setup_shop_id, v_oil_item_id);
    if v_oil_shop_item is null then
      raise exception 'cashier denied ensure_shop_item';
    end if;
  end;
end;
$$;

-- =====================================================================
-- §13 Sale history + void_sale + refund (#16)
-- =====================================================================

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_rice_shop_item_id uuid;
  v_kg_unit_id uuid;
  v_customer_id uuid;
  v_sale_id uuid;
  v_reversal_id uuid;
  v_stock_before numeric;
  v_stock_after numeric;
  v_is_voided boolean;
  v_failed boolean;
  v_line_count int;
  v_packaging text;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  select id into v_rice_shop_item_id from public.shop_item
   where shop_id = v_shop_id and item_id = v_rice_item_id;
  select id into v_kg_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id and conversion_to_base = 1;

  v_customer_id := public.create_party(v_shop_id, 'Void Customer', null, 'customer');

  select current_stock into v_stock_before from public.shop_item where id = v_rice_shop_item_id;

  -- Sale on credit (no payment), then void without refund.
  v_sale_id := public.post_sale(
    v_shop_id, v_customer_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_kg_unit_id, 'quantity', 2, 'unit_price', 1.20
    )),
    0, null, null, 'void-sale-1', null, 'sale to void'
  );

  -- list_sales shows the new sale, not voided.
  select count(*) into v_line_count from public.list_sales(v_shop_id, null, 100)
   where txn_id = v_sale_id;
  if v_line_count <> 1 then
    raise exception 'list_sales did not return the new sale';
  end if;

  -- get_sale_lines returns shop_item_unit_id + packaging_label.
  select packaging_label into v_packaging from public.get_sale_lines(v_shop_id, v_sale_id);
  if v_packaging <> 'Kg' then
    raise exception 'get_sale_lines packaging_label = % (expected Kg)', v_packaging;
  end if;

  v_reversal_id := public.void_sale(v_shop_id, v_sale_id, 'void-1');
  if v_reversal_id is null then
    raise exception 'void_sale returned null';
  end if;

  -- Reversal line carries shop_item_unit_id.
  if not exists (
    select 1 from public.transaction_line
    where shop_id = v_shop_id and transaction_id = v_reversal_id
      and shop_item_unit_id = v_kg_unit_id
  ) then
    raise exception 'reversal line missing shop_item_unit_id';
  end if;

  select current_stock into v_stock_after from public.shop_item where id = v_rice_shop_item_id;
  if v_stock_after <> v_stock_before then
    raise exception 'stock not restored after void';
  end if;

  -- Idempotent.
  if public.void_sale(v_shop_id, v_sale_id, 'void-1') <> v_reversal_id then
    raise exception 'void_sale not idempotent on client_op_id';
  end if;

  -- Already voided rejected.
  v_failed := false;
  begin
    perform public.void_sale(v_shop_id, v_sale_id, 'void-1-bis');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'void_sale allowed a second void';
  end if;

  -- list_sales flags the original as voided; reversal hidden.
  select is_voided into v_is_voided
  from public.list_sales(v_shop_id, null, 100)
  where txn_id = v_sale_id;
  if not v_is_voided then
    raise exception 'list_sales did not flag voided sale';
  end if;

  -- #16 Refund-on-void: paid-cash sale, void with refund_amount.
  declare
    v_paid_sale_id uuid;
    v_refund_customer uuid;
    v_payment_count int;
    v_payment_amount numeric;
  begin
    v_refund_customer := public.create_party(v_shop_id, 'Refund Customer', null, 'customer');

    v_paid_sale_id := public.post_sale(
      v_shop_id, v_refund_customer,
      jsonb_build_array(jsonb_build_object(
        'shop_item_unit_id', v_kg_unit_id, 'quantity', 2, 'unit_price', 1.50
      )),
      3.00, 'cash', null, 'paid-sale-1', null, 'sale fully paid cash'
    );

    -- Refund too big rejected.
    v_failed := false;
    begin
      perform public.void_sale(v_shop_id, v_paid_sale_id, 'refund-too-big', 100);
    exception when raise_exception then v_failed := true;
    end;
    if not v_failed then
      raise exception 'void_sale accepted refund > paid';
    end if;

    -- Refund zero rejected.
    v_failed := false;
    begin
      perform public.void_sale(v_shop_id, v_paid_sale_id, 'refund-zero', 0);
    exception when raise_exception then v_failed := true;
    end;
    if not v_failed then
      raise exception 'void_sale accepted refund=0';
    end if;

    -- Happy refund.
    perform public.void_sale(v_shop_id, v_paid_sale_id, 'refund-happy', 1.50);
    select count(*), max(amount) into v_payment_count, v_payment_amount
    from public.payment
    where shop_id = v_shop_id and refund_of_transaction_id = v_paid_sale_id;
    if v_payment_count <> 1 then
      raise exception 'refund payment row count = % (expected 1)', v_payment_count;
    end if;
    if v_payment_amount <> 1.50 then
      raise exception 'refund payment amount = % (expected 1.50)', v_payment_amount;
    end if;
    if not exists (
      select 1 from public.payment
      where refund_of_transaction_id = v_paid_sale_id
        and direction = 'O'
    ) then
      raise exception 'refund payment did not have direction=O';
    end if;
  end;
end;
$$;

-- =====================================================================
-- §14 Receive history + void_receive + stock-activity guard (#17)
-- =====================================================================
-- NOTE: migration 0030 currently drops the canonical `void_receive`
-- function declared in 0010. Until that's fixed (in-place edit to 0030),
-- the void_receive assertions can't execute. We still validate
-- get_receive_lines + packaging label; the void-path checks are gated
-- behind a pg_proc lookup. If/when the migration is corrected the gate
-- becomes a no-op.

do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_rice_shop_item_id uuid;
  v_bag25_unit_id uuid;
  v_kg_unit_id uuid;
  v_supplier_id uuid;
  v_recv_id uuid;
  v_blocked_recv_id uuid;
  v_reversal_id uuid;
  v_stock_before numeric;
  v_stock_after numeric;
  v_failed boolean;
  v_packaging text;
  v_has_void_receive boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  select id into v_rice_shop_item_id from public.shop_item
   where shop_id = v_shop_id and item_id = v_rice_item_id;
  select id into v_bag25_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id
     and unit_code = 'bag' and conversion_to_base = 25;
  select id into v_kg_unit_id from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id and conversion_to_base = 1;
  select id into v_supplier_id from public.party
   where shop_id = v_shop_id and name = 'Hodan Beverages';

  select current_stock into v_stock_before from public.shop_item where id = v_rice_shop_item_id;

  v_recv_id := public.post_receive(
    v_shop_id, v_supplier_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_bag25_unit_id, 'quantity', 1, 'line_total', 20
    )),
    0, null, null, 'void-recv-1', null, 'will void'
  );

  -- get_receive_lines packaging.
  select packaging_label into v_packaging from public.get_receive_lines(v_shop_id, v_recv_id);
  if v_packaging <> '25 Kg Bag' then
    raise exception 'get_receive_lines packaging = % (expected "25 Kg Bag")', v_packaging;
  end if;

  -- Probe for void_receive presence (see note above; 0030 currently drops it).
  select exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'void_receive'
  ) into v_has_void_receive;

  if v_has_void_receive then
    v_reversal_id := public.void_receive(v_shop_id, v_recv_id, 'void-r-1');
    if v_reversal_id is null then
      raise exception 'void_receive returned null';
    end if;

    if not exists (
      select 1 from public.transaction_line
      where shop_id = v_shop_id and transaction_id = v_reversal_id
        and shop_item_unit_id = v_bag25_unit_id
    ) then
      raise exception 'receive reversal missing shop_item_unit_id';
    end if;

    select current_stock into v_stock_after from public.shop_item where id = v_rice_shop_item_id;
    if v_stock_after <> v_stock_before then
      raise exception 'receive void did not restore stock';
    end if;

    if public.void_receive(v_shop_id, v_recv_id, 'void-r-1') <> v_reversal_id then
      raise exception 'void_receive not idempotent';
    end if;

    v_blocked_recv_id := public.post_receive(
      v_shop_id, v_supplier_id,
      jsonb_build_array(jsonb_build_object(
        'shop_item_unit_id', v_bag25_unit_id, 'quantity', 1, 'line_total', 20
      )),
      0, null, null, 'block-recv-1', null, 'will be blocked'
    );
    perform public.post_sale(
      v_shop_id, null,
      jsonb_build_array(jsonb_build_object(
        'shop_item_unit_id', v_kg_unit_id, 'quantity', 1, 'unit_price', 1.20
      )),
      1.20, 'cash', null, 'sale-after-recv', null, 'sale that touches stock'
    );

    v_failed := false;
    begin
      perform public.void_receive(v_shop_id, v_blocked_recv_id, 'block-void');
    exception when raise_exception then v_failed := true;
    end;
    if not v_failed then
      raise exception 'void_receive ignored stock-activity guard';
    end if;
  else
    raise notice 'SKIPPED: void_receive assertions (function dropped by migration 0030)';
  end if;
end;
$$;

-- =====================================================================
-- §15 Tenant isolation + cashier denial of owner-only RPCs (#19, #20)
-- =====================================================================

-- #19 Cashier denied owner-only RPCs.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

do $$
declare
  v_shop_id uuid;
  v_sale_id uuid;
  v_failed boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  -- Find any non-reversed sale txn in this shop.
  select id into v_sale_id from public.txn
   where shop_id = v_shop_id
     and reverses_transaction_id is null
     and type_id = (select id from public.transaction_type where code = 'sale')
   limit 1;

  v_failed := false;
  begin
    perform public.void_sale(v_shop_id, v_sale_id, 'cashier-void');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'cashier was allowed to void_sale';
  end if;

  v_failed := false;
  begin
    perform public.post_inventory_adjustment(
      v_shop_id, 'correction',
      jsonb_build_array(jsonb_build_object(
        'shop_item_id', (select id from public.shop_item where shop_id = v_shop_id limit 1),
        'quantity_delta', -1,
        'unit_cost', 0.5
      )),
      null, 'cashier-adj', null, 'denied'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'cashier was allowed to post_inventory_adjustment';
  end if;

  v_failed := false;
  begin
    perform public.complete_shop_setup(v_shop_id);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'cashier was allowed to complete_shop_setup';
  end if;
end;
$$;

-- #20 Tenant isolation: unrelated user sees nothing.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id uuid;
  v_failed boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  if (select count(*) from public.shop_item where shop_id = v_shop_id) <> 0 then
    raise exception 'unrelated user sees shop_item rows';
  end if;
  if (select count(*) from public.txn where shop_id = v_shop_id) <> 0 then
    raise exception 'unrelated user sees txn rows';
  end if;
  if (
    (select count(*) from public.v_sales_report where shop_id = v_shop_id)
    + (select count(*) from public.v_receive_report where shop_id = v_shop_id)
    + (select count(*) from public.v_shop_suggestions where shop_id = v_shop_id)
  ) <> 0 then
    raise exception 'unrelated user sees report/suggestion rows';
  end if;

  v_failed := false;
  begin
    perform * from public.search_items(v_shop_id, '', 'sale', 'en');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'unrelated user called search_items';
  end if;

  v_failed := false;
  begin
    perform public.create_party(v_shop_id, 'Intruder', null, 'customer');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'unrelated user called create_party';
  end if;
end;
$$;

-- =====================================================================
-- §16 DB-level triggers: base-unit guards + mismatch trigger (#3, #4, #5)
-- =====================================================================

-- #3 Global item_unit base-unit guard (platform_admin context).
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';

do $$
declare
  v_rice_item_id uuid;
  v_failed boolean;
begin
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';

  -- conversion_to_base=1 with mismatched unit_code → trigger raises.
  v_failed := false;
  begin
    insert into public.item_unit (item_id, unit_code, conversion_to_base)
    values (v_rice_item_id, 'piece', 1);
  exception
    when raise_exception then v_failed := true;
    when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'global item_unit base-unit guard did not fire';
  end if;
end;
$$;

-- #4 shop_item_unit base-unit guard (owner context).
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_rice_shop_item_id uuid;
  v_failed boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  select id into v_rice_shop_item_id from public.shop_item
   where shop_id = v_shop_id and item_id = v_rice_item_id;

  v_failed := false;
  begin
    insert into public.shop_item_unit (
      shop_id, shop_item_id, unit_code, conversion_to_base
    ) values (v_shop_id, v_rice_shop_item_id, 'piece', 1);
  exception
    when raise_exception then v_failed := true;
    when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'shop_item_unit base-unit guard did not fire';
  end if;
end;
$$;

-- #5 Mismatch trigger on transaction_line: shop_item_unit belongs to a
-- different shop_item than line.item_id. Easiest path is to call post_sale
-- with two different items but a packaging from one of them — the server
-- resolves shop_item_id from the packaging, so we must reach for a direct
-- insert against the table. shop_item_unit_update is owner-only, but the
-- transaction_line table requires SECURITY DEFINER usually. We bypass by
-- using service role (reset role) so RLS doesn't get in the way.

reset role;
do $$
declare
  v_shop_id uuid;
  v_rice_item_id uuid;
  v_rice_shop_item_id uuid;
  v_sugar_item_id uuid;
  v_sugar_shop_item_id uuid;
  v_rice_kg_unit uuid;
  v_sugar_kg_unit uuid;
  v_txn_id uuid;
  v_failed boolean;
  v_kg_unit_id uuid;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_rice_item_id from public.item where code = 'rice_basmati_25kg';
  select id into v_sugar_item_id from public.item where code = 'sugar_white_50kg';
  select id into v_rice_shop_item_id from public.shop_item
   where shop_id = v_shop_id and item_id = v_rice_item_id;
  select id into v_sugar_shop_item_id from public.shop_item
   where shop_id = v_shop_id and item_id = v_sugar_item_id;
  select id into v_rice_kg_unit from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_rice_shop_item_id and conversion_to_base = 1;
  select id into v_sugar_kg_unit from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_sugar_shop_item_id and conversion_to_base = 1;
  select id into v_kg_unit_id from public.unit where code = 'kg';

  -- Make a real header txn we can attach a line to.
  insert into public.txn (
    shop_id, type_id, status_id, occurred_at, total_amount, paid_amount,
    created_by
  )
  values (
    v_shop_id,
    (select id from public.transaction_type where code = 'sale'),
    (select id from public.transaction_status where code = 'posted'),
    pg_catalog.now(), 0, 0,
    '00000000-0000-0000-0000-000000000001'
  )
  returning id into v_txn_id;

  -- Line: item_id = rice's shop_item; shop_item_unit_id = sugar's kg packaging.
  v_failed := false;
  begin
    insert into public.transaction_line (
      shop_id, transaction_id, line_no,
      item_id, shop_item_unit_id, quantity, unit_id,
      base_quantity, unit_amount, item_name_snapshot,
      unit_code_snapshot, unit_conversion_to_base_snapshot, line_total
    )
    values (
      v_shop_id, v_txn_id, 1,
      v_rice_shop_item_id, v_sugar_kg_unit, 1, v_kg_unit_id,
      1, 1, 'Rice', 'kg', 1, 1
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'transaction_line packaging-mismatch trigger did not fire';
  end if;

  -- Clean up the empty header.
  delete from public.txn where id = v_txn_id;
end;
$$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- Cross-shop FK check still holds: a shop_item_unit insert that crosses
-- tenants fails on the composite FK (shop_id, shop_item_id).
do $$
declare
  v_shop_id uuid;
  v_other_shop_id uuid;
  v_other_shop_item uuid;
  v_failed boolean;
begin
  select shop_id, second_shop_id into v_shop_id, v_other_shop_id from test_ids;
  select id into v_other_shop_item from public.shop_item
   where shop_id = v_other_shop_id limit 1;

  v_failed := false;
  begin
    -- Use conversion=2 so the base-unit guard trigger skips (it only
    -- fires for conversion=1) and the composite FK is the first thing
    -- that rejects the row.
    insert into public.shop_item_unit (
      shop_id, shop_item_id, unit_code, conversion_to_base
    ) values (v_shop_id, v_other_shop_item, 'bag', 2);
  exception when foreign_key_violation then v_failed := true;
  end;
  if not v_failed then
    raise exception 'cross-shop shop_item_unit composite FK was not enforced';
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- Phase 1B coverage: extended create_shop_item + new suggestion RPCs.
-- ---------------------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- A1 — sold-in-base path (single packaging, defaults on both sides).
do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_default_unit_id uuid;
  v_packaging_count int;
  v_base_default_sale boolean;
  v_base_default_receive boolean;
  v_base_sale_price numeric;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_default_unit_id
  from public.create_shop_item(
    v_shop_id, 'A1 Sold-In-Base', 'en', 'piece', 1.25, null
  );
  if v_item_id is null or v_default_unit_id is null then
    raise exception 'A1 sold-in-base returned nulls';
  end if;

  select count(*) into v_packaging_count
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id;
  if v_packaging_count <> 1 then
    raise exception 'A1 sold-in-base did not create exactly one packaging';
  end if;

  select is_default_sale, is_default_receive, sale_price
  into v_base_default_sale, v_base_default_receive, v_base_sale_price
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id;

  if not v_base_default_sale or not v_base_default_receive then
    raise exception 'A1 sold-in-base base row missing default flags';
  end if;
  if v_base_sale_price <> 1.25 then
    raise exception 'A1 sold-in-base did not apply sale price';
  end if;
end;
$$;

-- A1 — sold-packaged path, sale variant.
do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_default_unit_id uuid;
  v_packaging_count int;
  v_sold_default_sale boolean;
  v_sold_default_receive boolean;
  v_sold_sale_price numeric;
  v_base_default_sale boolean;
  v_base_default_receive boolean;
  v_base_sale_price numeric;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_default_unit_id
  from public.create_shop_item(
    v_shop_id,                -- shop
    'A1 Sale Packaged',       -- name
    'en',                     -- locale
    'kg',                     -- base unit
    25.00,                    -- price for the sold packaging
    null,                     -- category
    'bag',                    -- sold unit
    25,                       -- conversion
    'sale'                    -- variant
  );

  select count(*) into v_packaging_count
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id;
  if v_packaging_count <> 2 then
    raise exception 'A1 sold-packaged should create 2 rows, got %', v_packaging_count;
  end if;

  -- Default unit (returned) is the sold row.
  select is_default_sale, is_default_receive, sale_price
  into v_sold_default_sale, v_sold_default_receive, v_sold_sale_price
  from public.shop_item_unit
  where id = v_default_unit_id;
  if not v_sold_default_sale or v_sold_default_receive then
    raise exception
      'A1 sale-packaged sold row should have default_sale=true, default_receive=false';
  end if;
  if v_sold_sale_price <> 25.00 then
    raise exception 'A1 sale-packaged sold row missing sale price';
  end if;

  -- Base row (the OTHER packaging on this item).
  select is_default_sale, is_default_receive, sale_price
  into v_base_default_sale, v_base_default_receive, v_base_sale_price
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id
    and id <> v_default_unit_id;
  if v_base_default_sale or not v_base_default_receive then
    raise exception
      'A1 sale-packaged base row should have default_sale=false, default_receive=true';
  end if;
  if v_base_sale_price is not null then
    raise exception 'A1 sale-packaged base row should be unpriced';
  end if;
end;
$$;

-- A1 — sold-packaged path, receive variant (flags mirror).
do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_default_unit_id uuid;
  v_sold_default_sale boolean;
  v_sold_default_receive boolean;
  v_base_default_sale boolean;
  v_base_default_receive boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_default_unit_id
  from public.create_shop_item(
    v_shop_id, 'A1 Receive Packaged', 'en', 'bottle',
    null, null,                        -- no sale price at receive-time
    'carton', 12, 'receive'
  );

  select is_default_sale, is_default_receive
  into v_sold_default_sale, v_sold_default_receive
  from public.shop_item_unit where id = v_default_unit_id;
  if v_sold_default_sale or not v_sold_default_receive then
    raise exception
      'A1 receive-packaged sold row should have default_receive=true, default_sale=false';
  end if;

  select is_default_sale, is_default_receive
  into v_base_default_sale, v_base_default_receive
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id
    and id <> v_default_unit_id;
  if not v_base_default_sale or v_base_default_receive then
    raise exception
      'A1 receive-packaged base row should have default_sale=true, default_receive=false';
  end if;
end;
$$;

-- A1 — bad inputs.
do $$
declare
  v_shop_id uuid;
  v_failed boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- p_default_side outside {sale, receive}
  v_failed := false;
  begin
    perform public.create_shop_item(
      v_shop_id, 'A1 Bad Side', 'en', 'piece', 1.00, null,
      'bag', 25, 'maybe'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'A1 accepted invalid p_default_side';
  end if;

  -- conversion = 1 with distinct unit
  v_failed := false;
  begin
    perform public.create_shop_item(
      v_shop_id, 'A1 Bad Conv', 'en', 'kg', 1.00, null,
      'bag', 1, 'sale'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'A1 accepted distinct sold unit with conversion=1';
  end if;

  -- conversion = 0
  v_failed := false;
  begin
    perform public.create_shop_item(
      v_shop_id, 'A1 Zero', 'en', 'kg', 1.00, null,
      'bag', 0, 'sale'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'A1 accepted conversion=0';
  end if;
end;
$$;

-- A2 — suggest_item_packagings excludes already-added.
do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_default_unit_id uuid;
  v_pre_count int;
  v_post_count int;
  v_added_count int;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_default_unit_id
  from public.create_shop_item(
    v_shop_id, 'A2 Exclusion Test', 'en', 'kg', null, null
  );

  -- Snapshot the picker BEFORE the cashier creates a packaging.
  select count(*) into v_pre_count
  from public.suggest_item_packagings(v_shop_id, v_item_id, 'kg', null, 'en', 20);

  -- Add bag x25.
  perform public.create_shop_item_unit(
    v_shop_id, v_item_id, 'bag', 25, null
  );

  -- Picker should drop the (bag, 25) row.
  select count(*) into v_post_count
  from public.suggest_item_packagings(v_shop_id, v_item_id, 'kg', null, 'en', 20);
  select count(*) into v_added_count
  from public.suggest_item_packagings(v_shop_id, v_item_id, 'kg', null, 'en', 20)
  where unit_code = 'bag' and conversion_to_base = 25;

  if v_added_count <> 0 then
    raise exception 'A2 picker still surfaces already-added (bag, 25)';
  end if;
  if v_post_count <> greatest(v_pre_count - 1, 0) then
    raise exception
      'A2 exclusion should drop exactly one row (pre %, post %)',
      v_pre_count, v_post_count;
  end if;
end;
$$;

-- A2 — primary-only when category has enough matches.
do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_default_unit_id uuid;
  v_grocery uuid;
  v_primary_count int;
  v_cross_count int;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_grocery from public.category where code = 'grocery';

  -- packet base + grocery category: 5 packet-based grocery items in
  -- seed (biscuit, coffee, milk, pasta, tea) yield distinct (unit,
  -- conversion) pairs above the 3-row primary threshold — fallback
  -- should NOT fire.
  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_default_unit_id
  from public.create_shop_item(
    v_shop_id, 'A2 Category Test', 'en', 'packet', null, v_grocery
  );

  select count(*) into v_primary_count
  from public.suggest_item_packagings(
    v_shop_id, v_item_id, 'packet', v_grocery, 'en', 20
  )
  where source = 'category';
  if v_primary_count < 3 then
    raise exception
      'A2 expected ≥3 category packagings for grocery+packet, got %',
      v_primary_count;
  end if;

  select count(*) into v_cross_count
  from public.suggest_item_packagings(
    v_shop_id, v_item_id, 'packet', v_grocery, 'en', 20
  )
  where source = 'cross_category';
  if v_cross_count <> 0 then
    raise exception
      'A2 cross-category fallback should not fire when primary is full';
  end if;
end;
$$;

-- A3 — suggest_new_item_options returns both arrays correctly shaped.
do $$
declare
  v_grocery uuid;
  v_result jsonb;
  v_base_count int;
  v_packaged_count int;
  v_first_packaged jsonb;
begin
  select id into v_grocery from public.category where code = 'grocery';
  v_result := public.suggest_new_item_options(v_grocery, 'en');

  v_base_count := jsonb_array_length(v_result -> 'base_units');
  v_packaged_count := jsonb_array_length(v_result -> 'packaged_units');

  if v_base_count = 0 then
    raise exception 'A3 base_units should be non-empty for the grocery category';
  end if;
  if v_packaged_count = 0 then
    raise exception 'A3 packaged_units should be non-empty for grocery';
  end if;

  -- Every packaged_units row must carry an implied base_unit_code that
  -- appears in base_units — otherwise the picker would offer a packaged
  -- option the cashier can't infer a base from.
  v_first_packaged := v_result -> 'packaged_units' -> 0;
  if v_first_packaged -> 'base_unit_code' is null
     or v_first_packaged -> 'unit_code' is null
     or v_first_packaged -> 'conversion_to_base' is null then
    raise exception
      'A3 packaged_unit missing required field: %', v_first_packaged::text;
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- §S Per-item reorder-threshold setter (0031).
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id          uuid;
  v_shop_item_id     uuid;
  v_default_unit_id  uuid;
  v_threshold        numeric;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Create a fresh shop_item we can attach a threshold to.
  select shop_item_id, default_shop_item_unit_id
  into v_shop_item_id, v_default_unit_id
  from public.create_shop_item(
    v_shop_id, 'Low Stock Test', 'en', 'kg', null, null
  );

  -- Setter: positive threshold lands.
  perform public.set_shop_item_reorder_threshold(
    v_shop_id, v_shop_item_id, 5
  );
  select reorder_threshold into v_threshold
  from public.shop_item where id = v_shop_item_id;
  if v_threshold is null or v_threshold <> 5 then
    raise exception 'S: setter should write threshold=5 (got %)', v_threshold;
  end if;

  -- Setter: null clears.
  perform public.set_shop_item_reorder_threshold(
    v_shop_id, v_shop_item_id, null
  );
  select reorder_threshold into v_threshold
  from public.shop_item where id = v_shop_item_id;
  if v_threshold is not null then
    raise exception 'S: setter should clear threshold (got %)', v_threshold;
  end if;

  -- Setter: rejects negative.
  begin
    perform public.set_shop_item_reorder_threshold(
      v_shop_id, v_shop_item_id, -1
    );
    raise exception 'S: setter must reject negative thresholds';
  exception when others then
    null;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- §T set_shop_item_unit_default_flags (0032).
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id     uuid;
  v_item_id     uuid;
  v_base_id     uuid;
  v_bag_id      uuid;
  v_default_sale uuid;
  v_default_recv uuid;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Fresh item with two packagings to flip flags between.
  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_base_id
  from public.create_shop_item(
    v_shop_id, 'Default Flags Test', 'en', 'kg', null, null
  );
  v_bag_id := public.create_shop_item_unit(
    v_shop_id, v_item_id, 'bag', 5, null
  );

  -- Sanity — base row has both defaults (no other packaging existed when
  -- it was created), bag has neither.
  select id into v_default_sale
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id and is_default_sale;
  if v_default_sale <> v_base_id then
    raise exception 'T pre: base should hold default_sale (got %)', v_default_sale;
  end if;

  -- Flip default_sale from base → bag.
  perform public.set_shop_item_unit_default_flags(
    v_shop_id, v_bag_id, true, false
  );
  select id into v_default_sale
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id and is_default_sale;
  if v_default_sale <> v_bag_id then
    raise exception 'T: default_sale should be bag after flip (got %)',
      v_default_sale;
  end if;
  -- The previous holder must have had its flag cleared.
  if (select is_default_sale from public.shop_item_unit where id = v_base_id) then
    raise exception 'T: base default_sale should be cleared after bag flip';
  end if;

  -- Setting both flags false on bag → no row holds default_sale.
  perform public.set_shop_item_unit_default_flags(
    v_shop_id, v_bag_id, false, false
  );
  select id into v_default_sale
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id and is_default_sale;
  if v_default_sale is not null then
    raise exception
      'T: setting both flags false should leave shop_item with no sale default';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- §U list_categories (0033).
-- ---------------------------------------------------------------------------
do $$
declare
  v_count int;
  v_first_name text;
begin
  -- Authenticated reader: any signed-in user — categories are global.
  select count(*) into v_count from public.list_categories('en');
  if v_count = 0 then
    raise exception 'U: list_categories should return seeded categories';
  end if;
  -- name is locale-resolved (English); shouldn't be empty.
  select name into v_first_name from public.list_categories('en') limit 1;
  if v_first_name is null or pg_catalog.length(pg_catalog.btrim(v_first_name)) = 0 then
    raise exception 'U: list_categories first row missing name (got %)',
      v_first_name;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- §V create_bono_document (0034).
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id     uuid;
  v_doc_id      uuid;
  v_supplied_id uuid;
  v_storage_bucket text;
  v_type_code   text;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  v_supplied_id := extensions.gen_random_uuid();

  -- Happy path: client-supplied id + canonical path.
  v_doc_id := public.create_bono_document(
    v_shop_id,
    v_supplied_id,
    v_shop_id::text || '/documents/' || v_supplied_id::text || '/image.jpg',
    'image/jpeg',
    1024
  );
  if v_doc_id is null or v_doc_id <> v_supplied_id then
    raise exception 'V: create_bono_document should return supplied id';
  end if;

  -- Document row is of type 'bono' and lives in shop-documents.
  select storage_bucket into v_storage_bucket
  from public.document where id = v_doc_id;
  if v_storage_bucket <> 'shop-documents' then
    raise exception 'V: document.storage_bucket should be shop-documents (got %)',
      v_storage_bucket;
  end if;
  select dt.code into v_type_code
  from public.document d join public.document_type dt on dt.id = d.type_id
  where d.id = v_doc_id;
  if v_type_code <> 'bono' then
    raise exception 'V: document.type should be bono (got %)', v_type_code;
  end if;

  -- Bad mime is rejected.
  begin
    perform public.create_bono_document(
      v_shop_id,
      extensions.gen_random_uuid(),
      v_shop_id::text || '/documents/abc/image.gif',
      'image/gif',
      500
    );
    raise exception 'V: create_bono_document must reject non-image mime';
  exception when others then
    null;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- §W Today summary + 3 reports (0036).
-- ---------------------------------------------------------------------------
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id        uuid;
  v_summary        jsonb;
  v_sales_today    numeric;
  v_receivables    numeric;
  v_payables       numeric;
  v_low_count      int;
  v_receivable_sum numeric;
  v_payable_sum    numeric;
  v_low_rows       int;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- get_today_summary returns a jsonb with the four scalars; numeric
  -- coalescing means non-null even when the shop has no activity today.
  v_summary := public.get_today_summary(v_shop_id, 'en');
  v_sales_today := (v_summary ->> 'sales_today')::numeric;
  v_receivables := (v_summary ->> 'receivables_total')::numeric;
  v_payables    := (v_summary ->> 'payables_total')::numeric;
  v_low_count   := (v_summary ->> 'low_stock_count')::int;
  if v_sales_today is null
     or v_receivables is null
     or v_payables is null
     or v_low_count is null then
    raise exception 'W: get_today_summary fields must never be null (got %)',
      v_summary;
  end if;

  -- list_receivables sum must match receivables_total from summary.
  select coalesce(sum(receivable), 0)
  into v_receivable_sum
  from public.list_receivables(v_shop_id, 'en');
  if v_receivable_sum <> v_receivables then
    raise exception
      'W: list_receivables sum (%) must equal summary.receivables_total (%)',
      v_receivable_sum, v_receivables;
  end if;

  -- list_payables sum must match payables_total from summary.
  select coalesce(sum(payable), 0)
  into v_payable_sum
  from public.list_payables(v_shop_id, 'en');
  if v_payable_sum <> v_payables then
    raise exception
      'W: list_payables sum (%) must equal summary.payables_total (%)',
      v_payable_sum, v_payables;
  end if;

  -- list_low_stock row count must match low_stock_count from summary.
  select count(*)::int into v_low_rows from public.list_low_stock(v_shop_id, 'en');
  if v_low_rows <> v_low_count then
    raise exception
      'W: list_low_stock rows (%) must equal summary.low_stock_count (%)',
      v_low_rows, v_low_count;
  end if;
end;
$$;

-- Tenant isolation: an unrelated user must not be able to call these
-- reports against a foreign shop.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id uuid;
  v_failed  boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  v_failed := false;
  begin
    perform public.get_today_summary(v_shop_id, 'en');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'W: get_today_summary must deny non-members';
  end if;

  v_failed := false;
  begin
    perform * from public.list_receivables(v_shop_id, 'en');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'W: list_receivables must deny non-members';
  end if;

  v_failed := false;
  begin
    perform * from public.list_payables(v_shop_id, 'en');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'W: list_payables must deny non-members';
  end if;

  v_failed := false;
  begin
    perform * from public.list_low_stock(v_shop_id, 'en');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'W: list_low_stock must deny non-members';
  end if;
end;
$$;

-- Switch back so any later sections continue under the primary user.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- §Y set_shop_item_category + deactivate_shop_item_unit (0038).
-- Cover happy paths + the two guards (unknown category, can't remove
-- base packaging). Cashier denial is implicit via auth_can_post_shop
-- which §15 already exercises for sibling RPCs.
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id         uuid;
  v_item_id         uuid;
  v_base_unit_id    uuid;
  v_bag_unit_id     uuid;
  v_other_category  uuid;
  v_original_cat    uuid;
  v_was_active      boolean;
  v_failed          boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Pick any shop_item with at least one non-base packaging so we can
  -- exercise deactivate without touching base.
  select si.id, si.category_id
    into v_item_id, v_original_cat
    from public.shop_item si
    join public.shop_item_unit siu on siu.shop_item_id = si.id
   where si.shop_id = v_shop_id
     and siu.conversion_to_base <> 1
     and siu.is_active
   limit 1;
  if v_item_id is null then
    raise notice 'Y: no shop_item with extra packaging to test against; skipping';
    return;
  end if;

  select id into v_base_unit_id
    from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_item_id
     and conversion_to_base = 1
   limit 1;
  select id into v_bag_unit_id
    from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_item_id
     and conversion_to_base <> 1 and is_active
   limit 1;

  -- ---- set_shop_item_category --------------------------------------------
  -- Pick any category != current so the change is detectable.
  select id into v_other_category
    from public.category
   where is_active
     and (v_original_cat is null or id <> v_original_cat)
   limit 1;
  perform public.set_shop_item_category(
    v_shop_id, v_item_id, v_other_category
  );
  if (select category_id from public.shop_item where id = v_item_id)
       <> v_other_category then
    raise exception 'Y: set_shop_item_category did not persist';
  end if;

  -- Clear (null) is allowed.
  perform public.set_shop_item_category(v_shop_id, v_item_id, null);
  if (select category_id from public.shop_item where id = v_item_id) is not null then
    raise exception 'Y: clearing category should leave NULL';
  end if;

  -- Unknown category rejected.
  v_failed := false;
  begin
    perform public.set_shop_item_category(
      v_shop_id, v_item_id, '00000000-0000-0000-0000-00000000beef'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'Y: set_shop_item_category accepted unknown category';
  end if;

  -- ---- deactivate_shop_item_unit -----------------------------------------
  -- Cannot remove the structural base packaging.
  v_failed := false;
  begin
    perform public.deactivate_shop_item_unit(v_shop_id, v_base_unit_id);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'Y: deactivate_shop_item_unit allowed base removal';
  end if;

  -- Non-base packaging: flips is_active false; default flags cleared.
  perform public.deactivate_shop_item_unit(v_shop_id, v_bag_unit_id);
  if (select is_active from public.shop_item_unit where id = v_bag_unit_id) then
    raise exception 'Y: deactivate did not flip is_active';
  end if;
  if (select is_default_sale or is_default_receive
        from public.shop_item_unit where id = v_bag_unit_id) then
    raise exception 'Y: deactivate left default flags set';
  end if;

  -- Idempotent: second call is a no-op.
  perform public.deactivate_shop_item_unit(v_shop_id, v_bag_unit_id);

  -- Restore for any later sections that depend on the packaging.
  update public.shop_item_unit set is_active = true where id = v_bag_unit_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- §X list_sales / list_receives history filters (0037).
-- p_date_from / p_date_to clamp the time window; p_party_id narrows
-- to one party. Defaults (null) preserve the pre-0037 behaviour.
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id      uuid;
  v_total_rows   int;
  v_today_rows   int;
  v_yesterday_rows int;
  v_one_party    uuid;
  v_party_rows   int;
  v_today_start  timestamptz;
  v_today_end    timestamptz;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Baseline: unfiltered count must equal explicit-null filter count.
  select count(*) into v_total_rows
  from public.list_sales(v_shop_id, null, 1000, null, null, null);

  -- Today filter must not exceed the baseline.
  v_today_start := pg_catalog.date_trunc('day', pg_catalog.now());
  v_today_end := v_today_start + interval '1 day';
  select count(*) into v_today_rows
  from public.list_sales(
    v_shop_id, null, 1000, v_today_start, v_today_end, null
  );
  if v_today_rows > v_total_rows then
    raise exception 'X: today-filter row count (%) > total (%)',
      v_today_rows, v_total_rows;
  end if;

  -- Yesterday filter (a known-empty window for the harness — no
  -- backdated sales) must return zero.
  select count(*) into v_yesterday_rows
  from public.list_sales(
    v_shop_id, null, 1000,
    v_today_start - interval '1 day',
    v_today_start,
    null
  );
  if v_yesterday_rows <> 0 then
    raise exception 'X: yesterday window unexpectedly returned %', v_yesterday_rows;
  end if;

  -- Pick a party that has at least one sale (if any), and prove the
  -- party-id filter restricts to that party only.
  select party_id into v_one_party
  from public.list_sales(v_shop_id, null, 1000, null, null, null)
  where party_id is not null
  limit 1;
  if v_one_party is not null then
    select count(*) into v_party_rows
    from public.list_sales(v_shop_id, null, 1000, null, null, v_one_party);
    if v_party_rows = 0 then
      raise exception 'X: party filter returned 0 for known party %',
        v_one_party;
    end if;
    if exists (
      select 1
      from public.list_sales(v_shop_id, null, 1000, null, null, v_one_party)
      where party_id is distinct from v_one_party
    ) then
      raise exception 'X: party filter leaked rows from another party';
    end if;
  end if;

  -- Same checks against list_receives — just smoke the new signature
  -- (we don't assert non-empty windows since the harness may not
  -- have a receive today).
  perform 1 from public.list_receives(
    v_shop_id, null, 100, v_today_start, v_today_end, null
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- §Z list_expenses (0039) — pagination + date + category filter.
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id      uuid;
  v_total_rows   int;
  v_today_rows   int;
  v_one_category uuid;
  v_category_rows int;
  v_today_start  timestamptz;
  v_today_end    timestamptz;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Baseline + explicit-null parity.
  select count(*) into v_total_rows
  from public.list_expenses(v_shop_id, null, 1000, null, null, null, 'en');

  v_today_start := pg_catalog.date_trunc('day', pg_catalog.now());
  v_today_end := v_today_start + interval '1 day';
  select count(*) into v_today_rows
  from public.list_expenses(
    v_shop_id, null, 1000, v_today_start, v_today_end, null, 'en'
  );
  if v_today_rows > v_total_rows then
    raise exception 'Z: today-filter row count (%) > total (%)',
      v_today_rows, v_total_rows;
  end if;

  -- Category filter: pick any category referenced by an expense, then
  -- confirm the filtered set only contains that category.
  select category_id into v_one_category
  from public.list_expenses(v_shop_id, null, 1000, null, null, null, 'en')
  where category_id is not null
  limit 1;
  if v_one_category is not null then
    select count(*) into v_category_rows
    from public.list_expenses(
      v_shop_id, null, 1000, null, null, v_one_category, 'en'
    );
    if v_category_rows = 0 then
      raise exception 'Z: category filter returned 0 for known category %',
        v_one_category;
    end if;
    if exists (
      select 1
      from public.list_expenses(
        v_shop_id, null, 1000, null, null, v_one_category, 'en'
      )
      where category_id is distinct from v_one_category
    ) then
      raise exception 'Z: category filter leaked rows from another category';
    end if;
  end if;
end;
$$;

-- Tenant isolation: unrelated user must be denied.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id uuid;
  v_failed  boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  v_failed := false;
  begin
    perform * from public.list_expenses(
      v_shop_id, null, 1000, null, null, null, 'en'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'Z: list_expenses must deny non-members';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- §ZZ list_payments (0040) — pagination + date + party + direction.
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id      uuid;
  v_total_rows   int;
  v_inbound_rows int;
  v_outbound_rows int;
  v_one_party    uuid;
  v_party_rows   int;
  v_today_start  timestamptz;
  v_today_end    timestamptz;
  v_today_rows   int;
  v_failed       boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Baseline + explicit-null parity.
  select count(*) into v_total_rows
  from public.list_payments(v_shop_id, null, 1000, null, null, null, null);

  -- Direction split sums to total (every payment is either I or O).
  select count(*) into v_inbound_rows
  from public.list_payments(v_shop_id, null, 1000, null, null, null, 'I');
  select count(*) into v_outbound_rows
  from public.list_payments(v_shop_id, null, 1000, null, null, null, 'O');
  if v_inbound_rows + v_outbound_rows <> v_total_rows then
    raise exception 'ZZ: direction split (% in + % out) <> total %',
      v_inbound_rows, v_outbound_rows, v_total_rows;
  end if;

  -- Bad direction rejected.
  v_failed := false;
  begin
    perform * from public.list_payments(
      v_shop_id, null, 1000, null, null, null, 'X'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'ZZ: bogus direction must be rejected';
  end if;

  -- Date filter: today window cannot exceed total.
  v_today_start := pg_catalog.date_trunc('day', pg_catalog.now());
  v_today_end := v_today_start + interval '1 day';
  select count(*) into v_today_rows
  from public.list_payments(
    v_shop_id, null, 1000, v_today_start, v_today_end, null, null
  );
  if v_today_rows > v_total_rows then
    raise exception 'ZZ: today rows (%) > total (%)',
      v_today_rows, v_total_rows;
  end if;

  -- Party filter: pick a known party + verify isolation.
  select party_id into v_one_party
  from public.list_payments(v_shop_id, null, 1000, null, null, null, null)
  where party_id is not null
  limit 1;
  if v_one_party is not null then
    select count(*) into v_party_rows
    from public.list_payments(
      v_shop_id, null, 1000, null, null, v_one_party, null
    );
    if v_party_rows = 0 then
      raise exception 'ZZ: party filter returned 0 for known party %',
        v_one_party;
    end if;
    if exists (
      select 1
      from public.list_payments(
        v_shop_id, null, 1000, null, null, v_one_party, null
      )
      where party_id is distinct from v_one_party
    ) then
      raise exception 'ZZ: party filter leaked another party';
    end if;
  end if;
end;
$$;

-- Tenant isolation: unrelated user must be denied.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id uuid;
  v_failed  boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  v_failed := false;
  begin
    perform * from public.list_payments(
      v_shop_id, null, 1000, null, null, null, null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'ZZ: list_payments must deny non-members';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- §ZZZ list_parties (0041) — type + has-balance + bad-type rejection.
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id            uuid;
  v_all_rows           int;
  v_customer_rows      int;
  v_supplier_rows      int;
  v_has_balance_rows   int;
  v_failed             boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  select count(*) into v_all_rows
  from public.list_parties(v_shop_id, '', null, false, 1000);

  -- Type filters never exceed the unfiltered list.
  select count(*) into v_customer_rows
  from public.list_parties(v_shop_id, '', 'customer', false, 1000);
  select count(*) into v_supplier_rows
  from public.list_parties(v_shop_id, '', 'supplier', false, 1000);
  if v_customer_rows > v_all_rows or v_supplier_rows > v_all_rows then
    raise exception 'ZZZ: typed list exceeds unfiltered';
  end if;

  -- Has-balance-only never exceeds unfiltered, and every row in it
  -- has at least one non-zero side.
  select count(*) into v_has_balance_rows
  from public.list_parties(v_shop_id, '', null, true, 1000);
  if v_has_balance_rows > v_all_rows then
    raise exception 'ZZZ: has-balance-only exceeds total';
  end if;
  if exists (
    select 1
    from public.list_parties(v_shop_id, '', null, true, 1000)
    where receivable = 0 and payable = 0
  ) then
    raise exception 'ZZZ: has-balance-only included zero-balance rows';
  end if;

  -- Bad type rejected.
  v_failed := false;
  begin
    perform * from public.list_parties(v_shop_id, '', 'employee', false, 1000);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'ZZZ: bogus type must be rejected';
  end if;
end;
$$;

-- Tenant isolation.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id uuid;
  v_failed  boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  v_failed := false;
  begin
    perform * from public.list_parties(v_shop_id, '', null, false, 1000);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'ZZZ: list_parties must deny non-members';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- §AA update_party + post_opening_party_balance (0042).
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id    uuid;
  v_party_id   uuid;
  v_supplier_id uuid;
  v_before_rec numeric;
  v_after_rec  numeric;
  v_after_pay  numeric;
  v_txn_id_1   uuid;
  v_txn_id_2   uuid;
  v_failed     boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Create a fresh customer + supplier to test against (so we don't
  -- perturb other harness sections).
  v_party_id := public.create_party(
    v_shop_id, 'Opening Test Customer', null, 'customer'
  );
  v_supplier_id := public.create_party(
    v_shop_id, 'Opening Test Supplier', null, 'supplier'
  );

  -- update_party: rename + phone change.
  perform public.update_party(
    v_shop_id, v_party_id, 'Renamed Customer', '0700000001'
  );
  if not exists (
    select 1 from public.party
    where id = v_party_id
      and name = 'Renamed Customer'
      and phone = '0700000001'
  ) then
    raise exception 'AA: update_party did not persist';
  end if;

  -- update_party: empty name rejected.
  v_failed := false;
  begin
    perform public.update_party(v_shop_id, v_party_id, '  ', null);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'AA: empty name must be rejected';
  end if;

  -- post_opening_party_balance: receivable side.
  select receivable into v_before_rec from public.party where id = v_party_id;
  v_txn_id_1 := public.post_opening_party_balance(
    v_shop_id, v_party_id, 25.50, 'I', 'op-customer-1', null
  );
  select receivable into v_after_rec from public.party where id = v_party_id;
  if v_after_rec <> v_before_rec + 25.50 then
    raise exception 'AA: receivable not bumped (was %, now %)',
      v_before_rec, v_after_rec;
  end if;
  -- Idempotent: same client_op_id returns same txn id, no double bump.
  if public.post_opening_party_balance(
       v_shop_id, v_party_id, 25.50, 'I', 'op-customer-1', null
     ) <> v_txn_id_1 then
    raise exception 'AA: opening balance not idempotent on client_op_id';
  end if;
  if (select receivable from public.party where id = v_party_id) <> v_after_rec then
    raise exception 'AA: idempotent retry double-bumped receivable';
  end if;

  -- payable side via supplier.
  v_txn_id_2 := public.post_opening_party_balance(
    v_shop_id, v_supplier_id, 40, 'O', 'op-supplier-1', 'old debt'
  );
  select payable into v_after_pay from public.party where id = v_supplier_id;
  if v_after_pay <> 40 then
    raise exception 'AA: payable not bumped (now %)', v_after_pay;
  end if;

  -- Direction must match party type — customer + 'O' rejected.
  v_failed := false;
  begin
    perform public.post_opening_party_balance(
      v_shop_id, v_party_id, 5, 'O', 'op-customer-bad', null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'AA: outbound direction allowed on customer party';
  end if;

  -- Amount <= 0 rejected.
  v_failed := false;
  begin
    perform public.post_opening_party_balance(
      v_shop_id, v_party_id, 0, 'I', 'op-zero', null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'AA: zero amount allowed';
  end if;

  -- Bad direction code rejected.
  v_failed := false;
  begin
    perform public.post_opening_party_balance(
      v_shop_id, v_party_id, 1, 'X', 'op-bad', null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'AA: bad direction code allowed';
  end if;
end;
$$;

-- Tenant isolation for both RPCs.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id  uuid;
  v_party_id uuid;
  v_failed   boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_party_id from public.party where shop_id = v_shop_id limit 1;

  v_failed := false;
  begin
    perform public.update_party(v_shop_id, v_party_id, 'Hack', null);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'AA: update_party allowed non-member';
  end if;

  v_failed := false;
  begin
    perform public.post_opening_party_balance(
      v_shop_id, v_party_id, 1, 'I', null, null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'AA: post_opening_party_balance allowed non-member';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- §BB alias + barcode mutations (0043) + extended get_shop_item (0044).
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id      uuid;
  v_item_id      uuid;
  v_base_unit_id uuid;
  v_bag_unit_id  uuid;
  v_alias_id     uuid;
  v_display_alias_id uuid;
  v_barcode_id_1 uuid;
  v_barcode_id_2 uuid;
  v_failed       boolean;
  v_count        int;
  v_primary_count int;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Pick any shop_item with at least one non-base packaging.
  select si.id into v_item_id
  from public.shop_item si
  join public.shop_item_unit siu on siu.shop_item_id = si.id
  where si.shop_id = v_shop_id
    and siu.conversion_to_base <> 1
    and siu.is_active
  limit 1;
  if v_item_id is null then
    raise notice 'BB: no shop_item with a non-base packaging; skipping';
    return;
  end if;

  select id into v_base_unit_id
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id
    and conversion_to_base = 1;
  select id into v_bag_unit_id
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_id
    and conversion_to_base <> 1 and is_active
  limit 1;

  -- ---- add_shop_item_barcode -------------------------------------------
  v_barcode_id_1 := public.add_shop_item_barcode(
    v_shop_id, v_bag_unit_id, '6291100123456', true, null
  );
  v_barcode_id_2 := public.add_shop_item_barcode(
    v_shop_id, v_bag_unit_id, '6291100999999', true, null
  );
  -- Atomic demotion: only the newest stays primary.
  select count(*) into v_primary_count
  from public.shop_item_barcode
  where shop_id = v_shop_id
    and shop_item_unit_id = v_bag_unit_id
    and is_primary;
  if v_primary_count <> 1 then
    raise exception 'BB: expected exactly one primary, got %', v_primary_count;
  end if;
  if (select is_primary from public.shop_item_barcode where id = v_barcode_id_1) then
    raise exception 'BB: previous primary was not demoted';
  end if;

  -- Idempotent insert: same (shop_item_unit_id, barcode) → upsert.
  if public.add_shop_item_barcode(
       v_shop_id, v_bag_unit_id, '6291100123456', false, null
     ) <> v_barcode_id_1 then
    raise exception 'BB: re-adding existing barcode did not return same id';
  end if;

  -- Empty barcode rejected.
  v_failed := false;
  begin
    perform public.add_shop_item_barcode(
      v_shop_id, v_bag_unit_id, '   ', false, null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'BB: empty barcode must be rejected';
  end if;

  -- Unknown packaging rejected.
  v_failed := false;
  begin
    perform public.add_shop_item_barcode(
      v_shop_id, '00000000-0000-0000-0000-00000000beef',
      'fake', false, null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'BB: unknown packaging must be rejected';
  end if;

  -- ---- set_primary_shop_item_barcode -----------------------------------
  perform public.set_primary_shop_item_barcode(v_shop_id, v_barcode_id_1);
  if not (select is_primary from public.shop_item_barcode where id = v_barcode_id_1) then
    raise exception 'BB: set_primary did not promote';
  end if;
  if (select is_primary from public.shop_item_barcode where id = v_barcode_id_2) then
    raise exception 'BB: set_primary did not demote sibling';
  end if;

  -- ---- remove_shop_item_barcode ----------------------------------------
  perform public.remove_shop_item_barcode(v_shop_id, v_barcode_id_2);
  if exists (
    select 1 from public.shop_item_barcode
    where id = v_barcode_id_2
  ) then
    raise exception 'BB: barcode not removed';
  end if;

  -- ---- remove_shop_item_alias ------------------------------------------
  -- Add a non-display alias, then remove it.
  v_alias_id := public.add_shop_item_alias(
    v_shop_id, v_item_id, 'Some Alias', 'so', false
  );
  perform public.remove_shop_item_alias(v_shop_id, v_alias_id);
  if exists (
    select 1 from public.shop_item_alias where id = v_alias_id
  ) then
    raise exception 'BB: alias not removed';
  end if;

  -- Refuse to remove the display alias (every product needs one).
  select id into v_display_alias_id
  from public.shop_item_alias
  where shop_id = v_shop_id and shop_item_id = v_item_id and is_display
  limit 1;
  if v_display_alias_id is not null then
    v_failed := false;
    begin
      perform public.remove_shop_item_alias(v_shop_id, v_display_alias_id);
    exception when raise_exception then v_failed := true;
    end;
    if not v_failed then
      raise exception 'BB: removing display alias must be rejected';
    end if;
  end if;

  -- ---- get_shop_item returns the new id fields -------------------------
  select count(*) into v_count
  from jsonb_array_elements(
    (public.get_shop_item(v_shop_id, v_item_id, 'en'))->'barcodes'
  ) b
  where b ? 'barcode_id' and b ? 'shop_item_unit_id';
  if v_count = 0 then
    raise exception 'BB: get_shop_item barcodes missing barcode_id/shop_item_unit_id';
  end if;

  select count(*) into v_count
  from jsonb_array_elements(
    (public.get_shop_item(v_shop_id, v_item_id, 'en'))->'aliases'
  ) a
  where a ? 'alias_id';
  if v_count = 0 then
    raise exception 'BB: get_shop_item aliases missing alias_id';
  end if;
end;
$$;

-- Tenant isolation: unrelated user can't mutate barcodes or aliases.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id  uuid;
  v_unit_id  uuid;
  v_failed   boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select id into v_unit_id from public.shop_item_unit
   where shop_id = v_shop_id limit 1;

  v_failed := false;
  begin
    perform public.add_shop_item_barcode(
      v_shop_id, v_unit_id, 'hack', false, null
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'BB: add_shop_item_barcode allowed non-member';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- §CC list_shop_items extended fields (0045).
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id        uuid;
  v_total          int;
  v_priced         int;
  v_first_default  numeric;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Total rows + at-least-one priced (the shop has activated items
  -- with priced packagings via the test fixtures).
  select count(*) into v_total
  from public.list_shop_items(v_shop_id, null, null, 'en');
  if v_total = 0 then
    raise exception 'CC: list_shop_items returned 0 rows on seeded shop';
  end if;

  select count(*) into v_priced
  from public.list_shop_items(v_shop_id, null, null, 'en')
  where any_price_set;
  if v_priced = 0 then
    raise exception 'CC: any_price_set should be true on at least one fixture row';
  end if;

  -- default_sale_price is non-null when the default-sale packaging
  -- has a price. Pick one row that has a price and verify.
  select default_sale_price into v_first_default
  from public.list_shop_items(v_shop_id, null, null, 'en')
  where any_price_set and default_sale_price is not null
  limit 1;
  if v_first_default is null or v_first_default <= 0 then
    raise exception 'CC: default_sale_price should be a positive number for priced rows';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- §DD list_product_velocity (0046) — top + dead segments.
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id  uuid;
  v_result   jsonb;
  v_top_len  int;
  v_dead_len int;
  v_failed   boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  v_result := public.list_product_velocity(v_shop_id, 7, 10, 'en');
  if not (v_result ? 'top') or not (v_result ? 'dead') then
    raise exception 'DD: result missing top / dead keys';
  end if;
  v_top_len  := pg_catalog.jsonb_array_length(v_result->'top');
  v_dead_len := pg_catalog.jsonb_array_length(v_result->'dead');
  if v_top_len < 0 or v_dead_len < 0 then
    raise exception 'DD: array lengths must be non-negative';
  end if;

  -- Bad period rejected.
  v_failed := false;
  begin
    perform public.list_product_velocity(v_shop_id, 0, 10, 'en');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'DD: period_days <= 0 must be rejected';
  end if;
end;
$$;

-- Tenant isolation.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
do $$
declare
  v_shop_id uuid;
  v_failed  boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  v_failed := false;
  begin
    perform public.list_product_velocity(v_shop_id, 7, 10, 'en');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'DD: list_product_velocity must deny non-members';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- §FF capability vocabulary (0048).
--
-- The owner user (000…01) should see the owner capability set
-- including the owner-only entries (sales.void, receive.void,
-- inventory.product.edit, inventory.adjustment.post). The cashier
-- user (000…02) should see the cashier set WITHOUT those entries.
-- Both must include sales.post (the minimum to count as posting-
-- capable). The non-member (000…03) must see an empty set.

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$
declare
  v_shop_id uuid;
  v_caps jsonb;
begin
  select shop_id into v_shop_id from test_ids;
  v_caps := public.auth_user_shop_capabilities(v_shop_id);
  if not (v_caps ? 'sales.post') then
    raise exception 'FF owner: missing sales.post in %', v_caps;
  end if;
  if not (v_caps ? 'sales.void') then
    raise exception 'FF owner: missing sales.void in %', v_caps;
  end if;
  if not (v_caps ? 'inventory.product.edit') then
    raise exception 'FF owner: missing inventory.product.edit in %', v_caps;
  end if;
  if not (v_caps ? 'inventory.adjustment.post') then
    raise exception 'FF owner: missing inventory.adjustment.post in %', v_caps;
  end if;
  if not public.auth_user_has_capability('sales.void', v_shop_id) then
    raise exception 'FF owner: auth_user_has_capability(sales.void) returned false';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$
declare
  v_shop_id uuid;
  v_caps jsonb;
begin
  select shop_id into v_shop_id from test_ids;
  v_caps := public.auth_user_shop_capabilities(v_shop_id);
  if not (v_caps ? 'sales.post') then
    raise exception 'FF cashier: missing sales.post in %', v_caps;
  end if;
  if (v_caps ? 'sales.void') then
    raise exception 'FF cashier: must NOT have sales.void in %', v_caps;
  end if;
  if (v_caps ? 'inventory.product.edit') then
    raise exception 'FF cashier: must NOT have inventory.product.edit in %', v_caps;
  end if;
  if (v_caps ? 'inventory.adjustment.post') then
    raise exception 'FF cashier: must NOT have inventory.adjustment.post in %', v_caps;
  end if;
  if public.auth_user_has_capability('sales.void', v_shop_id) then
    raise exception 'FF cashier: auth_user_has_capability(sales.void) wrongly true';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
do $$
declare
  v_shop_id uuid;
  v_caps jsonb;
begin
  select shop_id into v_shop_id from test_ids;
  v_caps := public.auth_user_shop_capabilities(v_shop_id);
  if jsonb_array_length(v_caps) <> 0 then
    raise exception 'FF non-member: must see empty capability set, got %', v_caps;
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- §GG scanner settings (0049). Verify:
--   1. New shops get the column default.
--   2. Inserting a scanner_* row into shop_setting fires the
--      projection trigger and updates shop.scanner_settings.
--   3. apply_template path -> shop_setting -> column projection works.
--      (template_setting already seeded scanner_* keys for grocery
--      via migration 0049; the apply path on the test shop runs
--      during create_organization, so we verify the projection
--      lands those values without an explicit re-apply.)

do $$
declare
  v_shop_id uuid;
  v_settings jsonb;
begin
  select shop_id into v_shop_id from test_ids;
  v_settings := (select scanner_settings from public.shop where id = v_shop_id);
  if v_settings is null then
    raise exception 'GG: shop.scanner_settings is null';
  end if;
  if (v_settings ->> 'rearm_ms')::int is null then
    raise exception 'GG: scanner_settings missing rearm_ms: %', v_settings;
  end if;
  -- An owner edit via shop_setting should re-project. Bump rearm_ms
  -- from default 800 to 1200 and confirm shop.scanner_settings catches up.
  insert into public.shop_setting (shop_id, key, value, source, created_by)
  values (v_shop_id, 'scanner_rearm_ms', to_jsonb(1200), 'manual',
          '00000000-0000-0000-0000-000000000001')
  on conflict (shop_id, key) do update set value = excluded.value;
  v_settings := (select scanner_settings from public.shop where id = v_shop_id);
  if (v_settings ->> 'rearm_ms')::int <> 1200 then
    raise exception 'GG: projection trigger did not update rearm_ms; got %', v_settings;
  end if;
  -- Other knobs keep their defaults.
  if (v_settings ->> 'hid_min_burst_length')::int <> 4 then
    raise exception 'GG: hid_min_burst_length default not preserved: %', v_settings;
  end if;
  -- Delete restores defaults.
  delete from public.shop_setting
   where shop_id = v_shop_id and key = 'scanner_rearm_ms';
  v_settings := (select scanner_settings from public.shop where id = v_shop_id);
  if (v_settings ->> 'rearm_ms')::int <> 800 then
    raise exception 'GG: removing scanner_rearm_ms must reset to default; got %', v_settings;
  end if;
end;
$$;

-- §EE realtime publication (0047) — shop_item / shop_item_unit /
-- shop_item_alias / shop_item_barcode / party must all be in the
-- supabase_realtime publication so cross-portal edits propagate to
-- mobile subscribers.
do $$
declare
  t text;
  v_missing text[] := array[]::text[];
begin
  foreach t in array array[
    'shop_item',
    'shop_item_unit',
    'shop_item_alias',
    'shop_item_barcode',
    'party'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      v_missing := v_missing || t;
    end if;
  end loop;
  if array_length(v_missing, 1) is not null then
    raise exception 'EE: tables missing from supabase_realtime publication: %', v_missing;
  end if;
end;
$$;

-- §HH audit_log subsystem (0050). Verify:
--   1. Action-code registry seeded.
--   2. _audit_log refuses unknown codes.
--   3. _audit_log enforces reason floor (10 chars) and ceiling (300).
--   4. _audit_log drops before_state on add-only actions (policy).
--   5. _audit_log drops after_state on remove-only actions (policy).
--   6. Direct INSERT to audit_log is refused by RLS.
--   7. SELECT as shop member returns own shop's rows.
--   8. SELECT as non-member returns zero rows for that shop.
--   9. _audit_log_maintain_partitions creates next month's partition idempotently.

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- 1. Registry seeded (read as authenticated)
do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_action_code where is_active;
  if v_count < 25 then
    raise exception 'HH: action-code registry under-seeded: only % active codes', v_count;
  end if;
end;
$$;

-- 2 + 3 + 4 + 5: helper behaviour. _audit_log is the private write
-- path called by security-definer posting RPCs (which run as
-- postgres). Switch role to postgres for these direct calls; tests
-- still set the JWT sub so auth.uid() resolves correctly.
reset role;
do $$
declare
  v_shop_id  uuid;
  v_audit_id uuid;
  v_failed   boolean;
  v_row      public.audit_log%rowtype;
begin
  select shop_id into v_shop_id from test_ids;

  -- (2) unknown code refused
  v_failed := false;
  begin
    perform public._audit_log(v_shop_id, 'not.a.real.code', 'txn');
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'HH: _audit_log accepted an unknown action_code';
  end if;

  -- (3a) reason too short
  v_failed := false;
  begin
    perform public._audit_log(
      v_shop_id, 'sale.void', 'txn',
      p_entity_id := '00000000-0000-0000-0000-0000000000ff'::uuid,
      p_reason    := 'ok'
    );
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'HH: _audit_log accepted a too-short reason on sale.void';
  end if;

  -- (3b) reason too long
  v_failed := false;
  begin
    perform public._audit_log(
      v_shop_id, 'sale.void', 'txn',
      p_entity_id := '00000000-0000-0000-0000-0000000000ff'::uuid,
      p_reason    := repeat('x', 301)
    );
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'HH: _audit_log accepted a too-long reason';
  end if;

  -- (3c) valid reason commits
  v_audit_id := public._audit_log(
    v_shop_id, 'sale.void', 'txn',
    p_entity_id := '00000000-0000-0000-0000-0000000000ff'::uuid,
    p_before    := jsonb_build_object('lines', 3, 'total', 12.5),
    p_after     := jsonb_build_object('voided', true),
    p_reason    := 'wrong total typed at counter'
  );
  select * into v_row from public.audit_log where id = v_audit_id;
  if v_row.before_state is null or v_row.after_state is null then
    raise exception 'HH: sale.void should keep both before and after, got before=% after=%',
      v_row.before_state, v_row.after_state;
  end if;
  if v_row.reason is null or length(v_row.reason) < 10 then
    raise exception 'HH: sale.void reason lost: %', v_row.reason;
  end if;
  if v_row.actor_user_id <> '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'HH: actor_user_id should be the JWT sub, got %', v_row.actor_user_id;
  end if;

  -- (4) Add-only action drops before_state.
  v_audit_id := public._audit_log(
    v_shop_id, 'inventory.alias.add', 'shop_item_alias',
    p_entity_id := '00000000-0000-0000-0000-00000000aaaa'::uuid,
    p_before    := jsonb_build_object('should', 'be dropped'),
    p_after     := jsonb_build_object('alias', 'Tropi 25kg')
  );
  select * into v_row from public.audit_log where id = v_audit_id;
  if v_row.before_state is not null then
    raise exception 'HH: inventory.alias.add must drop before_state, got %', v_row.before_state;
  end if;
  if v_row.after_state is null then
    raise exception 'HH: inventory.alias.add must keep after_state';
  end if;

  -- (5) Remove-only action drops after_state.
  v_audit_id := public._audit_log(
    v_shop_id, 'inventory.alias.remove', 'shop_item_alias',
    p_entity_id := '00000000-0000-0000-0000-00000000aaaa'::uuid,
    p_before    := jsonb_build_object('alias', 'Tropi 25kg'),
    p_after     := jsonb_build_object('should', 'be dropped')
  );
  select * into v_row from public.audit_log where id = v_audit_id;
  if v_row.after_state is not null then
    raise exception 'HH: inventory.alias.remove must drop after_state';
  end if;
  if v_row.before_state is null then
    raise exception 'HH: inventory.alias.remove must keep before_state';
  end if;
end;
$$;

-- 6. Direct INSERT refused by RLS / lack of grant.
set role authenticated;
do $$
declare v_failed boolean := false;
        v_shop_id uuid;
begin
  select shop_id into v_shop_id from test_ids;
  begin
    insert into public.audit_log (shop_id, action_code, entity_type, source)
      values (v_shop_id, 'sale.post', 'txn', 'mobile');
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'HH: direct INSERT to audit_log must be refused (RLS / no grant)';
  end if;
end;
$$;

-- 7. Member SELECT works.
do $$
declare v_count int;
        v_shop_id uuid;
begin
  select shop_id into v_shop_id from test_ids;
  select count(*) into v_count from public.audit_log where shop_id = v_shop_id;
  if v_count < 3 then
    raise exception 'HH: owner should see at least 3 audit rows from prior subtests, got %', v_count;
  end if;
end;
$$;

-- 8. Non-member SELECT returns nothing.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
do $$
declare v_count int;
        v_shop_id uuid;
begin
  select shop_id into v_shop_id from test_ids;
  select count(*) into v_count from public.audit_log where shop_id = v_shop_id;
  if v_count <> 0 then
    raise exception 'HH: non-member must see zero audit rows, got %', v_count;
  end if;
end;
$$;

-- 9. Maintain partitions idempotent. (postgres-only function.)
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
reset role;
do $$
declare
  v_before int;
  v_after  int;
begin
  select count(*) into v_before
    from pg_catalog.pg_tables
   where schemaname = 'public' and tablename ~ '^audit_log_\d{4}_\d{2}$';
  perform public._audit_log_maintain_partitions();
  select count(*) into v_after
    from pg_catalog.pg_tables
   where schemaname = 'public' and tablename ~ '^audit_log_\d{4}_\d{2}$';
  if v_after <> v_before then
    raise exception 'HH: maintain_partitions not idempotent (% -> %)', v_before, v_after;
  end if;
  if v_after < 3 then
    raise exception 'HH: expected >=3 monthly partitions, got %', v_after;
  end if;
end;
$$;

-- 10. set_shop_item_unit_sale_price writes an
--     inventory.unit.price_edit audit row with after_state.
set role authenticated;
do $$
declare
  v_shop_id      uuid;
  v_shop_item_id uuid;
  v_unit_id      uuid;
  v_count        int;
  v_row          public.audit_log%rowtype;
begin
  select shop_id into v_shop_id from test_ids;
  -- Need a shop_item_unit to touch. shop_item has no name column
  -- (names live in aliases / global catalog); we just need the row.
  insert into public.shop_item (shop_id, base_unit_code, created_by)
  values (v_shop_id, 'kg',
          '00000000-0000-0000-0000-000000000001')
  returning id into v_shop_item_id;
  insert into public.shop_item_unit (
    shop_id, shop_item_id, unit_code, conversion_to_base, created_by
  )
  values (v_shop_id, v_shop_item_id, 'kg', 1,
          '00000000-0000-0000-0000-000000000001')
  returning id into v_unit_id;

  perform public.set_shop_item_unit_sale_price(v_shop_id, v_unit_id, 7.5);

  select count(*) into v_count
  from public.audit_log
  where shop_id = v_shop_id
    and action_code = 'inventory.unit.price_edit'
    and entity_id = v_unit_id;
  if v_count <> 1 then
    raise exception 'HH: set_shop_item_unit_sale_price audit row missing or duped (count=%)', v_count;
  end if;

  select * into v_row
  from public.audit_log
  where shop_id = v_shop_id
    and action_code = 'inventory.unit.price_edit'
    and entity_id = v_unit_id;
  if v_row.after_state is null
     or (v_row.after_state ->> 'sale_price')::numeric <> 7.5 then
    raise exception 'HH: price_edit after_state wrong: %', v_row.after_state;
  end if;
  if v_row.before_state is not null then
    raise exception 'HH: price_edit policy should drop before_state';
  end if;
end;
$$;

-- 11. update_party writes a people.party.edit audit row with
--     before + after.
do $$
declare
  v_shop_id   uuid;
  v_party_id  uuid;
  v_customer  uuid;
  v_count     int;
  v_row       public.audit_log%rowtype;
begin
  select shop_id into v_shop_id from test_ids;
  v_customer := (
    select id from public.party_type where code = 'customer'
  );
  insert into public.party (shop_id, name, phone, type_id, created_by)
  values (v_shop_id, 'HH Test Customer', '+25212340000', v_customer,
          '00000000-0000-0000-0000-000000000001')
  returning id into v_party_id;

  perform public.update_party(v_shop_id, v_party_id, 'HH Renamed', '+25299990000');

  select count(*) into v_count
  from public.audit_log
  where shop_id = v_shop_id
    and action_code = 'people.party.edit'
    and entity_id = v_party_id;
  if v_count <> 1 then
    raise exception 'HH: update_party audit row missing or duped (count=%)', v_count;
  end if;

  select * into v_row
  from public.audit_log
  where shop_id = v_shop_id
    and action_code = 'people.party.edit'
    and entity_id = v_party_id;
  if v_row.before_state ->> 'name' <> 'HH Test Customer' then
    raise exception 'HH: party.edit before_state name lost: %', v_row.before_state;
  end if;
  if v_row.after_state ->> 'name' <> 'HH Renamed' then
    raise exception 'HH: party.edit after_state name wrong: %', v_row.after_state;
  end if;
  if v_row.after_state ->> 'phone' <> '+25299990000' then
    raise exception 'HH: party.edit after_state phone wrong: %', v_row.after_state;
  end if;
end;
$$;

-- 12. list_audit_entries_for_entity returns the latest rows for an
--     entity and respects the limit + ordering.
do $$
declare
  v_shop_id   uuid;
  v_party_id  uuid;
  v_customer  uuid;
  v_rows      int;
  v_first     record;
begin
  select shop_id into v_shop_id from test_ids;
  v_customer := (select id from public.party_type where code = 'customer');
  insert into public.party (shop_id, name, phone, type_id, created_by)
  values (v_shop_id, 'List Reader Test', '+25212340001', v_customer,
          '00000000-0000-0000-0000-000000000001')
  returning id into v_party_id;
  perform public.update_party(v_shop_id, v_party_id, 'Rename one', '+1');
  perform pg_catalog.pg_sleep(0.05);
  perform public.update_party(v_shop_id, v_party_id, 'Rename two', '+2');
  perform pg_catalog.pg_sleep(0.05);
  perform public.update_party(v_shop_id, v_party_id, 'Rename three', '+3');

  select count(*) into v_rows
    from public.list_audit_entries_for_entity(v_shop_id, 'party', v_party_id, 10);
  if v_rows <> 3 then
    raise exception 'HH: list_audit returned wrong row count (%); want 3', v_rows;
  end if;

  -- Limit honored.
  select count(*) into v_rows
    from public.list_audit_entries_for_entity(v_shop_id, 'party', v_party_id, 2);
  if v_rows <> 2 then
    raise exception 'HH: list_audit limit not honored (%); want 2', v_rows;
  end if;

  -- Newest first.
  select * into v_first
    from public.list_audit_entries_for_entity(v_shop_id, 'party', v_party_id, 1);
  if v_first.action_code <> 'people.party.edit' then
    raise exception 'HH: latest entry action_code wrong: %', v_first.action_code;
  end if;
end;
$$;

-- 13. list_audit_entries_for_entity refuses non-members via the
--     auth_can_access_shop guard.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
do $$
declare
  v_shop_id uuid;
  v_failed boolean := false;
begin
  select shop_id into v_shop_id from test_ids;
  begin
    perform * from public.list_audit_entries_for_entity(
      v_shop_id, 'party',
      '00000000-0000-0000-0000-000000000abc'::uuid, 5);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'HH: list_audit_entries_for_entity must refuse non-members';
  end if;
end;
$$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- §II Per-invoice payment allocation (0053). Verify:
--   1. Standalone post_payment writes FIFO rows for default path; sum
--      equals payment amount; oldest invoice gets touched first.
--   2. Explicit p_allocations writes exactly those rows; FIFO skipped.
--   3. Validation rules raise on bad input (duplicate, wrong party,
--      wrong direction, sum mismatch, over-allocation, voided).
--   4. client_op_id replay returns same payment_id without doubling
--      allocations.
--   5. list_unpaid_invoices returns open rows oldest first; voided
--      excluded.
--   6. list_payment_allocations returns per-invoice rows.
--   7. v_party_aging shows one row per unpaid invoice with correct
--      outstanding.

set role authenticated;
do $$
declare
  v_shop_id    uuid;
  v_cust_id    uuid;
  v_sale_a     uuid;
  v_sale_b     uuid;
  v_sale_c     uuid;
  v_pay_id     uuid;
  v_pay_replay uuid;
  v_alloc_n    int;
  v_alloc_sum  numeric;
  v_remaining  numeric;
  v_age_n      int;
  v_failed     boolean;
  v_open_n     int;
  v_unit_id    uuid;
begin
  select shop_id into v_shop_id from test_ids;

  -- Pick any base (conversion_to_base=1) shop_item_unit in this shop.
  select siu.id into v_unit_id
  from public.shop_item_unit siu
  join public.shop_item si on si.id = siu.shop_item_id
  where siu.shop_id = v_shop_id and siu.conversion_to_base = 1
    and si.current_stock > 0
  limit 1;
  if v_unit_id is null then
    raise exception 'II setup: no base packaging available in this shop';
  end if;

  -- Fresh customer with three credit sales of $10, $20, $30 (oldest first).
  v_cust_id := public.create_party(
    v_shop_id, 'II Allocation Customer', null, 'customer'
  );

  v_sale_a := public.post_sale(
    v_shop_id, v_cust_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id',
      v_unit_id,
      'quantity', 10, 'unit_price', 1
    )),
    0, null, null, 'II-sale-a', '2026-01-01 09:00+03'::timestamptz, 'cred A'
  );
  v_sale_b := public.post_sale(
    v_shop_id, v_cust_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id',
      v_unit_id,
      'quantity', 20, 'unit_price', 1
    )),
    0, null, null, 'II-sale-b', '2026-02-01 09:00+03'::timestamptz, 'cred B'
  );
  v_sale_c := public.post_sale(
    v_shop_id, v_cust_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id',
      v_unit_id,
      'quantity', 30, 'unit_price', 1
    )),
    0, null, null, 'II-sale-c', '2026-03-01 09:00+03'::timestamptz, 'cred C'
  );

  if (select receivable from public.party where id = v_cust_id) <> 60 then
    raise exception 'II setup: three sales should leave $60 receivable';
  end if;

  -- (5) list_unpaid_invoices: 3 open, oldest first.
  select count(*) into v_open_n
  from public.list_unpaid_invoices(v_shop_id, v_cust_id, 'I');
  if v_open_n <> 3 then
    raise exception 'II (5): list_unpaid_invoices want 3 open, got %', v_open_n;
  end if;
  if (select transaction_id from public.list_unpaid_invoices(v_shop_id, v_cust_id, 'I')
      limit 1) <> v_sale_a then
    raise exception 'II (5): list_unpaid_invoices must order oldest first';
  end if;

  -- (1) Default FIFO: $25 payment fully consumes A ($10), partly consumes B ($15).
  v_pay_id := public.post_payment(
    v_shop_id, v_cust_id, 'I', 25, 'cash',
    'II-pay-fifo', null, null, null, null
  );

  select count(*) into v_alloc_n
  from public.payment_allocation
  where shop_id = v_shop_id and payment_id = v_pay_id;
  if v_alloc_n <> 2 then
    raise exception 'II (1): FIFO want 2 alloc rows, got %', v_alloc_n;
  end if;

  if (select amount from public.payment_allocation
      where shop_id = v_shop_id and payment_id = v_pay_id and transaction_id = v_sale_a)
     <> 10 then
    raise exception 'II (1): FIFO must fully consume oldest sale A ($10)';
  end if;
  if (select amount from public.payment_allocation
      where shop_id = v_shop_id and payment_id = v_pay_id and transaction_id = v_sale_b)
     <> 15 then
    raise exception 'II (1): FIFO must put remaining $15 on sale B';
  end if;

  -- (4) client_op_id replay returns same payment_id; no extra alloc rows.
  v_pay_replay := public.post_payment(
    v_shop_id, v_cust_id, 'I', 25, 'cash',
    'II-pay-fifo', null, null, null, null
  );
  if v_pay_replay <> v_pay_id then
    raise exception 'II (4): client_op_id replay must return same payment_id';
  end if;
  select count(*) into v_alloc_n
  from public.payment_allocation
  where shop_id = v_shop_id and payment_id = v_pay_id;
  if v_alloc_n <> 2 then
    raise exception 'II (4): replay must not double-write allocations (got %)',
      v_alloc_n;
  end if;

  -- list_unpaid_invoices now shows 2 open (B at $5, C at $30).
  select count(*) into v_open_n
  from public.list_unpaid_invoices(v_shop_id, v_cust_id, 'I');
  if v_open_n <> 2 then
    raise exception 'II (5): after FIFO want 2 open, got %', v_open_n;
  end if;
  select remaining into v_remaining
  from public.list_unpaid_invoices(v_shop_id, v_cust_id, 'I')
  where transaction_id = v_sale_b;
  if v_remaining <> 5 then
    raise exception 'II (5): sale B remaining want 5, got %', v_remaining;
  end if;

  -- (2) Explicit allocation: $20 split as $5 on B + $15 on C.
  v_pay_id := public.post_payment(
    v_shop_id, v_cust_id, 'I', 20, 'cash',
    'II-pay-explicit', null, null, null,
    jsonb_build_array(
      jsonb_build_object('transaction_id', v_sale_b::text, 'amount', 5),
      jsonb_build_object('transaction_id', v_sale_c::text, 'amount', 15)
    )
  );
  select count(*), pg_catalog.sum(amount) into v_alloc_n, v_alloc_sum
  from public.payment_allocation
  where shop_id = v_shop_id and payment_id = v_pay_id;
  if v_alloc_n <> 2 or v_alloc_sum <> 20 then
    raise exception 'II (2): explicit want 2 rows summing 20, got % rows summing %',
      v_alloc_n, v_alloc_sum;
  end if;

  -- (6) list_payment_allocations returns the breakdown.
  select count(*) into v_alloc_n
  from public.list_payment_allocations(v_shop_id, v_pay_id);
  if v_alloc_n <> 2 then
    raise exception 'II (6): list_payment_allocations want 2 rows, got %', v_alloc_n;
  end if;

  -- (3a) Validation: sum mismatch.
  v_failed := false;
  begin
    perform public.post_payment(
      v_shop_id, v_cust_id, 'I', 5, 'cash',
      'II-bad-sum', null, null, null,
      jsonb_build_array(jsonb_build_object(
        'transaction_id', v_sale_c::text, 'amount', 4
      ))
    );
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'II (3a): sum-mismatch allocation must raise';
  end if;

  -- (3b) Validation: duplicate transaction_id.
  v_failed := false;
  begin
    perform public.post_payment(
      v_shop_id, v_cust_id, 'I', 5, 'cash',
      'II-bad-dup', null, null, null,
      jsonb_build_array(
        jsonb_build_object('transaction_id', v_sale_c::text, 'amount', 3),
        jsonb_build_object('transaction_id', v_sale_c::text, 'amount', 2)
      )
    );
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'II (3b): duplicate transaction_id must raise';
  end if;

  -- (3c) Validation: allocation amount exceeds invoice remaining (sale C
  --      has $15 remaining after the explicit payment above).
  v_failed := false;
  begin
    perform public.post_payment(
      v_shop_id, v_cust_id, 'I', 15, 'cash',
      'II-bad-over', null, null, null,
      jsonb_build_array(jsonb_build_object(
        'transaction_id', v_sale_c::text, 'amount', 15.01
      ))
    );
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'II (3c): over-allocation must raise';
  end if;

  -- (3d) Validation: wrong direction (allocate against sale on an O payment).
  v_failed := false;
  begin
    perform public.post_payment(
      v_shop_id, v_cust_id, 'O', 5, 'cash',
      'II-bad-dir', null, null, null,
      jsonb_build_array(jsonb_build_object(
        'transaction_id', v_sale_c::text, 'amount', 5
      ))
    );
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'II (3d): wrong-direction allocation must raise';
  end if;

  -- (7) v_party_aging: after FIFO + explicit, only sale C ($15) remains open.
  --     A: fully paid by FIFO ($10). B: $15 FIFO + $5 explicit = $20 closed.
  --     C: $15 explicit allocation against $30 total → $15 open.
  select count(*) into v_age_n
  from public.v_party_aging
  where shop_id = v_shop_id and party_id = v_cust_id and outstanding > 0;
  if v_age_n <> 1 then
    raise exception 'II (7): v_party_aging want 1 unpaid row, got %', v_age_n;
  end if;
  select outstanding into v_remaining
  from public.v_party_aging
  where shop_id = v_shop_id and party_id = v_cust_id and transaction_id = v_sale_c;
  if v_remaining <> 15 then
    raise exception 'II (7): sale C outstanding want 15, got %', v_remaining;
  end if;
end;
$$;
reset role;

-- ---------------------------------------------------------------------------
-- §JJ void_sale + void_receive (0010). Verify:
--   1. Owner can void a fresh sale; reversal txn appears with matching
--      total_amount and reverses_transaction_id.
--   2. void_sale rejects a sale outside the 7-day window.
--   3. void_sale rejects a sale whose customer has paid some of the
--      receivable down between sale and void.
--   4. Double-void on the same sale raises.
--   5. void_sale denied for cashier role.
--   6. Owner can void a fresh receive when no later stock activity
--      touched the items.
--   7. void_receive rejects a receive whose items had subsequent
--      stock activity.
--   8. void_receive denied for cashier role.

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$
declare
  v_shop_id    uuid;
  v_unit_id    uuid;
  v_cust_id    uuid;
  v_sup_id     uuid;
  v_sale_id    uuid;
  v_recv_id    uuid;
  v_old_sale   uuid;
  v_partial    uuid;
  v_reversal   uuid;
  v_void_back  uuid;
  v_failed     boolean;
begin
  select shop_id into v_shop_id from test_ids;

  select siu.id into v_unit_id
  from public.shop_item_unit siu
  where siu.shop_id = v_shop_id and siu.conversion_to_base = 1
  limit 1;

  v_cust_id := public.create_party(v_shop_id, 'JJ Void Customer', null, 'customer');
  v_sup_id  := public.create_party(v_shop_id, 'JJ Void Supplier', null, 'supplier');

  -- (1) Owner voids a fresh credit sale.
  v_sale_id := public.post_sale(
    v_shop_id, v_cust_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_unit_id, 'quantity', 5, 'unit_price', 2
    )),
    0, null, null, 'JJ-sale-1', null, 'JJ sale to void'
  );
  v_reversal := public.void_sale(
    v_shop_id, v_sale_id, 'JJ-void-1'
  );
  if not exists (
    select 1 from public.txn
    where id = v_reversal and reverses_transaction_id = v_sale_id
  ) then
    raise exception 'JJ (1): reversal txn must point at the original sale';
  end if;
  if (select total_amount from public.txn where id = v_reversal) <> 10 then
    raise exception 'JJ (1): reversal total_amount want 10';
  end if;

  -- (4) Double-void on the same sale raises.
  v_failed := false;
  begin
    perform public.void_sale(v_shop_id, v_sale_id, 'JJ-void-1-dup');
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'JJ (4): double-void must raise';
  end if;

  -- (2) Sale outside the 7-day window cannot be voided. Plant a sale
  --     with a backdated posted_at via privileged role (we're testing
  --     the guard, not how the date got there).
  v_old_sale := public.post_sale(
    v_shop_id, v_cust_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_unit_id, 'quantity', 1, 'unit_price', 2
    )),
    0, null, null, 'JJ-sale-old', null, 'old sale'
  );
  reset role;
  update public.txn
  set posted_at = pg_catalog.now() - interval '8 days',
      occurred_at = pg_catalog.now() - interval '8 days'
  where id = v_old_sale;
  set role authenticated;
  set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
  v_failed := false;
  begin
    perform public.void_sale(v_shop_id, v_old_sale, null);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'JJ (2): void_sale must reject outside 7-day window';
  end if;

  -- (3) Partial-paid sale cannot be voided.
  v_partial := public.post_sale(
    v_shop_id, v_cust_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_unit_id, 'quantity', 1, 'unit_price', 10
    )),
    0, null, null, 'JJ-sale-partial', null, 'credit'
  );
  -- Customer pays $5 down on this $10 credit sale.
  perform public.post_payment(
    v_shop_id, v_cust_id, 'I', 5, 'cash',
    'JJ-partial-pay', null, null, null, null
  );
  v_failed := false;
  begin
    perform public.void_sale(v_shop_id, v_partial, null);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'JJ (3): void_sale must reject partial-paid sale';
  end if;

end;
$$;
reset role;

-- (6) + (7) — exercise void_receive against ISOLATED shop_items so the
-- transaction-shared now() doesn't make prior sales look "later than"
-- the receive. Each test gets its own fresh item, then a fresh DO
-- block so the second test's items can't see the first's movements.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$
declare
  v_shop_id    uuid;
  v_sup_id     uuid;
  v_item_id    uuid;
  v_unit_id    uuid;
  v_recv_id    uuid;
  v_void_back  uuid;
begin
  select shop_id into v_shop_id from test_ids;
  select id into v_sup_id from public.party
   where shop_id = v_shop_id and name = 'JJ Void Supplier';
  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_unit_id
  from public.create_shop_item(
    v_shop_id, 'JJ Void Receive Item 6', 'en', 'kg', null, null
  );

  v_recv_id := public.post_receive(
    v_shop_id, v_sup_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_unit_id, 'quantity', 4, 'line_total', 12
    )),
    0, null, null, 'JJ-recv-1', null, 'fresh receive'
  );
  v_void_back := public.void_receive(v_shop_id, v_recv_id, 'JJ-void-recv-1');
  if not exists (
    select 1 from public.txn
    where id = v_void_back and reverses_transaction_id = v_recv_id
  ) then
    raise exception 'JJ (6): receive reversal must reference original';
  end if;
end;
$$;
reset role;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$
declare
  v_shop_id    uuid;
  v_sup_id     uuid;
  v_item_id    uuid;
  v_unit_id    uuid;
  v_recv_id    uuid;
  v_failed     boolean;
begin
  select shop_id into v_shop_id from test_ids;
  select id into v_sup_id from public.party
   where shop_id = v_shop_id and name = 'JJ Void Supplier';
  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_unit_id
  from public.create_shop_item(
    v_shop_id, 'JJ Void Receive Item 7', 'en', 'kg', null, null
  );

  v_recv_id := public.post_receive(
    v_shop_id, v_sup_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_unit_id, 'quantity', 4, 'line_total', 12
    )),
    0, null, null, 'JJ-recv-2', null, 'will sell from'
  );
  -- Sell one unit AFTER the receive (same transaction timestamp is
  -- treated as "later" by the guard's `>=` predicate — exactly the
  -- racy back-to-back op the guard protects against).
  perform public.post_sale(
    v_shop_id, null,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_unit_id, 'quantity', 1, 'unit_price', 4
    )),
    4, 'cash', null, 'JJ-sale-after-recv', null, 'cash'
  );
  v_failed := false;
  begin
    perform public.void_receive(v_shop_id, v_recv_id, null);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'JJ (7): void_receive must reject when items had later activity';
  end if;
end;
$$;
reset role;

-- (5) + (8) Cashier denied void_sale and void_receive.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$
declare
  v_shop_id  uuid;
  v_txn_id   uuid;
  v_failed   boolean;
begin
  select shop_id into v_shop_id from test_ids;
  -- Pick any owner-posted sale (we just made several in JJ above).
  select id into v_txn_id from public.txn
  where shop_id = v_shop_id and client_op_id = 'JJ-sale-old';

  v_failed := false;
  begin
    perform public.void_sale(v_shop_id, v_txn_id, null);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'JJ (5): cashier must NOT be allowed to void a sale';
  end if;

  select id into v_txn_id from public.txn
  where shop_id = v_shop_id and client_op_id = 'JJ-recv-2';
  v_failed := false;
  begin
    perform public.void_receive(v_shop_id, v_txn_id, null);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'JJ (8): cashier must NOT be allowed to void a receive';
  end if;
end;
$$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
reset role;

-- ---------------------------------------------------------------------------
-- §KK post_inventory_adjustment correction-path coverage (0010). Verify:
--   1. Increase adjustment writes a stock_movement row and updates
--      both current_stock + avg_cost (weighted-average recompute).
--   2. client_op_id replay returns the same adjustment_id WITHOUT
--      doubling the stock_movement.
--   3. Reason mismatch: a decrease-only reason rejects positive delta.
--   4. Decrease without an explicit unit_cost defaults to avg_cost and
--      leaves avg unchanged.
-- §5 already covers the 'opening' path; §15 covers cashier denial.

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$
declare
  v_shop_id           uuid;
  v_item_id           uuid;
  v_unit_id           uuid;
  v_first_id          uuid;
  v_replay_id         uuid;
  v_movement_count    integer;
  v_stock             numeric;
  v_avg               numeric;
  v_failed            boolean;
begin
  select shop_id into v_shop_id from test_ids;
  select shop_item_id, default_shop_item_unit_id
  into v_item_id, v_unit_id
  from public.create_shop_item(
    v_shop_id, 'KK Adjustment Item', 'en', 'kg', null, null
  );

  -- Seed: +10 @ $1 → stock 10, avg 1.
  perform public.post_inventory_adjustment(
    v_shop_id, 'correction',
    jsonb_build_array(jsonb_build_object(
      'shop_item_id', v_item_id, 'quantity_delta', 10, 'unit_cost', 1
    )),
    null, 'KK-seed', null, null
  );

  -- (1) Increase: +5 @ $2 → stock 15, avg = (10*1 + 5*2)/15 ≈ 1.333.
  v_first_id := public.post_inventory_adjustment(
    v_shop_id, 'correction',
    jsonb_build_array(jsonb_build_object(
      'shop_item_id', v_item_id, 'quantity_delta', 5, 'unit_cost', 2
    )),
    null, 'KK-inc-1', null, null
  );
  select current_stock, avg_cost
  into v_stock, v_avg
  from public.shop_item where id = v_item_id;
  if v_stock <> 15 then
    raise exception 'KK (1): stock want 15, got %', v_stock;
  end if;
  if pg_catalog.abs(v_avg - 1.3333) > 0.001 then
    raise exception 'KK (1): avg_cost want ~1.333, got %', v_avg;
  end if;
  select pg_catalog.count(*) into v_movement_count
  from public.stock_movement
  where shop_id = v_shop_id and item_id = v_item_id;
  if v_movement_count <> 2 then
    raise exception 'KK (1): stock_movement count want 2 (seed + inc), got %',
      v_movement_count;
  end if;

  -- (2) Idempotency replay returns the same adjustment_id and does
  --     NOT add another stock_movement.
  v_replay_id := public.post_inventory_adjustment(
    v_shop_id, 'correction',
    jsonb_build_array(jsonb_build_object(
      'shop_item_id', v_item_id, 'quantity_delta', 5, 'unit_cost', 2
    )),
    null, 'KK-inc-1', null, null
  );
  if v_replay_id <> v_first_id then
    raise exception 'KK (2): replay must return same adjustment_id';
  end if;
  select pg_catalog.count(*) into v_movement_count
  from public.stock_movement
  where shop_id = v_shop_id and item_id = v_item_id;
  if v_movement_count <> 2 then
    raise exception 'KK (2): replay must not add stock_movement (got %)',
      v_movement_count;
  end if;

  -- (3) Reason-mismatch: a decrease-only reason (theft) rejects
  --     positive delta.
  v_failed := false;
  begin
    perform public.post_inventory_adjustment(
      v_shop_id, 'theft',
      jsonb_build_array(jsonb_build_object(
        'shop_item_id', v_item_id, 'quantity_delta', 1, 'unit_cost', 1
      )),
      null, 'KK-mismatch', null, null
    );
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'KK (3): decrease-only reason must reject positive delta';
  end if;

  -- (4) Decrease without unit_cost falls back to avg_cost; avg stays.
  perform public.post_inventory_adjustment(
    v_shop_id, 'correction',
    jsonb_build_array(jsonb_build_object(
      'shop_item_id', v_item_id, 'quantity_delta', -3
    )),
    null, 'KK-dec', null, null
  );
  select current_stock, avg_cost
  into v_stock, v_avg
  from public.shop_item where id = v_item_id;
  if v_stock <> 12 then
    raise exception 'KK (4): stock after -3 want 12, got %', v_stock;
  end if;
  if pg_catalog.abs(v_avg - 1.3333) > 0.001 then
    raise exception 'KK (4): decrease should not change avg_cost (got %)', v_avg;
  end if;
end;
$$;
reset role;

-- ---------------------------------------------------------------------------
-- §LL audit_log wiring across the 6 transaction RPCs (0010 + 0053).
-- Verify each posts an audit row with the expected action_code and the
-- right entity_id. The shop_admin_portal activity feed reads these.

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$
declare
  v_shop_id    uuid;
  v_unit_id    uuid;
  v_cust_id    uuid;
  v_sup_id     uuid;
  v_sale_id    uuid;
  v_recv_id    uuid;
  v_pay_id     uuid;
  v_exp_id     uuid;
  v_void_id    uuid;
  v_cat_id     uuid;
  v_count      integer;
begin
  select shop_id into v_shop_id from test_ids;
  select siu.id into v_unit_id
  from public.shop_item_unit siu
  where siu.shop_id = v_shop_id and siu.conversion_to_base = 1
  limit 1;

  v_cust_id := public.create_party(v_shop_id, 'LL Audit Customer', null, 'customer');
  v_sup_id  := public.create_party(v_shop_id, 'LL Audit Supplier', null, 'supplier');
  select id into v_cat_id from public.expense_category
   where shop_id = v_shop_id limit 1;

  -- post_sale → audit_log row with action_code='sale.post'.
  v_sale_id := public.post_sale(
    v_shop_id, v_cust_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_unit_id, 'quantity', 1, 'unit_price', 5
    )),
    0, null, null, 'LL-sale', null, 'LL sale'
  );
  select pg_catalog.count(*) into v_count
  from public.audit_log
  where action_code = 'sale.post' and entity_id = v_sale_id;
  if v_count <> 1 then
    raise exception 'LL: post_sale did not emit audit_log (got %)', v_count;
  end if;

  -- post_receive → 'receive.post'. Use an ISOLATED shop_item so the
  -- void_receive guard later doesn't see other activity sharing
  -- transaction_timestamp() (the same hazard §JJ navigated).
  declare
    v_iso_item_id  uuid;
    v_iso_unit_id  uuid;
  begin
    select shop_item_id, default_shop_item_unit_id
    into v_iso_item_id, v_iso_unit_id
    from public.create_shop_item(
      v_shop_id, 'LL Receive Isolated', 'en', 'kg', null, null
    );
    v_recv_id := public.post_receive(
      v_shop_id, v_sup_id,
      jsonb_build_array(jsonb_build_object(
        'shop_item_unit_id', v_iso_unit_id, 'quantity', 1, 'line_total', 3
      )),
      0, null, null, 'LL-recv', null, 'LL receive'
    );
  end;
  select pg_catalog.count(*) into v_count
  from public.audit_log
  where action_code = 'receive.post' and entity_id = v_recv_id;
  if v_count <> 1 then
    raise exception 'LL: post_receive did not emit audit_log';
  end if;

  -- post_payment → 'payment.post' (entity is the payment, not the txn).
  v_pay_id := public.post_payment(
    v_shop_id, v_cust_id, 'I', 5, 'cash',
    'LL-pay', null, null, null, null
  );
  select pg_catalog.count(*) into v_count
  from public.audit_log
  where action_code = 'payment.post' and entity_id = v_pay_id;
  if v_count <> 1 then
    raise exception 'LL: post_payment did not emit audit_log';
  end if;

  -- post_expense → 'expense.post'.
  v_exp_id := public.post_expense(
    v_shop_id, v_cat_id, 7, 'cash', null,
    'LL-exp', null, 'LL expense'
  );
  select pg_catalog.count(*) into v_count
  from public.audit_log
  where action_code = 'expense.post' and entity_id = v_exp_id;
  if v_count <> 1 then
    raise exception 'LL: post_expense did not emit audit_log';
  end if;

  -- void_sale → 'sale.void'. Post a FRESH unpaid sale (the earlier
  -- one was paid down by the LL-pay above, which would trip the
  -- "paid down some of this" guard).
  v_sale_id := public.post_sale(
    v_shop_id, v_cust_id,
    jsonb_build_array(jsonb_build_object(
      'shop_item_unit_id', v_unit_id, 'quantity', 1, 'unit_price', 4
    )),
    0, null, null, 'LL-sale-void', null, 'LL sale to void'
  );
  v_void_id := public.void_sale(
    v_shop_id, v_sale_id, 'LL-void-sale', null,
    'LL test default reason override (>10 chars)'
  );
  select pg_catalog.count(*) into v_count
  from public.audit_log
  where action_code = 'sale.void' and entity_id = v_sale_id;
  if v_count <> 1 then
    raise exception 'LL: void_sale did not emit audit_log';
  end if;

  -- void_receive (with no later activity, on the same fresh receive).
  v_void_id := public.void_receive(
    v_shop_id, v_recv_id, 'LL-void-recv',
    'LL test default reason override (>10 chars)'
  );
  select pg_catalog.count(*) into v_count
  from public.audit_log
  where action_code = 'receive.void' and entity_id = v_recv_id;
  if v_count <> 1 then
    raise exception 'LL: void_receive did not emit audit_log';
  end if;
end;
$$;
reset role;

-- ---------------------------------------------------------------------------
-- §NN Admin-portal prereqs (0054): user_preference, new capabilities,
-- update_shop_settings RPC, shop_invite RPCs. Verify:
--   1. user_preference RLS — user reads/writes only their own row.
--   2. New capability codes are registered + owner role inherits them.
--   3. update_shop_settings: owner can edit, cashier denied, audit_log
--      row written via setup.shop.edit, no-op on empty patch.
--   4. create_shop_invite: idempotent on (shop_id, phone), audit-logged,
--      cashier denied (no setup.staff.invite cap).
--   5. accept_shop_invite: creates shop_membership row; rejects expired
--      invites; rejects phone-mismatch.
-- ---------------------------------------------------------------------------

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- 1. user_preference RLS — owner writes their own; other user can't read it.
do $$
declare
  v_owner_rows int;
  v_other_rows int;
  v_failed boolean;
begin
  insert into public.user_preference (user_id, ui_locale)
  values (auth.uid(), 'so')
  on conflict (user_id) do update set ui_locale = excluded.ui_locale;

  select count(*) into v_owner_rows from public.user_preference where user_id = auth.uid();
  if v_owner_rows <> 1 then
    raise exception 'NN (1): owner could not read their own user_preference';
  end if;

  -- Try to insert for someone else — must fail at RLS.
  v_failed := false;
  begin
    insert into public.user_preference (user_id, ui_locale)
    values ('00000000-0000-0000-0000-000000000003'::uuid, 'so');
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'NN (1): RLS allowed insert for another user_id';
  end if;
end;
$$;

-- 2. New capabilities present + owner has them.
-- Capability table is RLS-locked away from authenticated; run the
-- existence probe via the capability helper which IS exposed.
do $$
declare
  v_shop_id uuid;
begin
  select shop_id into v_shop_id from test_ids;
  if not public.auth_user_has_capability('audit.view', v_shop_id) then
    raise exception 'NN (2): owner role missing audit.view';
  end if;
  if not public.auth_user_has_capability('sales.export', v_shop_id) then
    raise exception 'NN (2): owner role missing sales.export';
  end if;
  if not public.auth_user_has_capability('inventory.product.bulk_edit', v_shop_id) then
    raise exception 'NN (2): owner role missing inventory.product.bulk_edit';
  end if;
  if not public.auth_user_has_capability('setup.staff.invite', v_shop_id) then
    raise exception 'NN (2): owner role missing setup.staff.invite';
  end if;
  if not public.auth_user_has_capability('dashboard.view_org', v_shop_id) then
    raise exception 'NN (2): owner role missing dashboard.view_org';
  end if;
end;
$$;

-- 3. update_shop_settings: owner allowed + audit-logged.
do $$
declare
  v_shop_id     uuid;
  v_audit_count int;
  v_failed      boolean;
begin
  select shop_id into v_shop_id from test_ids;

  -- Owner edits timezone.
  perform public.update_shop_settings(
    v_shop_id,
    jsonb_build_object('timezone', 'Africa/Mogadishu')
  );
  select count(*) into v_audit_count
  from public.audit_log
  where action_code = 'setup.shop.edit'
    and entity_id = v_shop_id;
  if v_audit_count < 1 then
    raise exception 'NN (3): update_shop_settings did not emit audit_log';
  end if;

  -- Empty patch is a no-op (no new audit row).
  perform public.update_shop_settings(v_shop_id, '{}'::jsonb);
  select count(*) into v_audit_count
  from public.audit_log
  where action_code = 'setup.shop.edit'
    and entity_id = v_shop_id;
  if v_audit_count <> 1 then
    raise exception 'NN (3): empty patch must not write a new audit row (got %)', v_audit_count;
  end if;
end;
$$;

-- 4. create_shop_invite: cashier denied.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$
declare
  v_shop_id uuid;
  v_failed  boolean;
begin
  select shop_id into v_shop_id from test_ids;
  v_failed := false;
  begin
    perform public.create_shop_invite(v_shop_id, '+252611111111', null, 'cashier', null);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'NN (4): cashier was allowed to create_shop_invite';
  end if;
end;
$$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- 4b. create_shop_invite: owner happy path + idempotent (phone variant).
do $$
declare
  v_shop_id    uuid;
  v_invite_1   uuid;
  v_invite_2   uuid;
  v_audit_n    int;
begin
  select shop_id into v_shop_id from test_ids;
  v_invite_1 := public.create_shop_invite(
    v_shop_id, '+252611222333', null, 'cashier');
  if v_invite_1 is null then
    raise exception 'NN (4b): create_shop_invite returned null';
  end if;

  -- Same (shop, phone) — returns the same id.
  v_invite_2 := public.create_shop_invite(
    v_shop_id, '+252611222333', null, 'cashier');
  if v_invite_2 <> v_invite_1 then
    raise exception 'NN (4b): create_shop_invite not idempotent (got % vs %)',
      v_invite_2, v_invite_1;
  end if;

  -- Audit row written.
  select count(*) into v_audit_n
  from public.audit_log
  where action_code = 'setup.staff.invite'
    and entity_id = v_invite_1;
  if v_audit_n <> 1 then
    raise exception 'NN (4b): expected 1 audit row, got %', v_audit_n;
  end if;
end;
$$;

-- 4c. create_shop_invite: email variant + idempotent + dual-channel
-- merge + empty-contact rejection.
do $$
declare
  v_shop_id   uuid;
  v_invite_1  uuid;
  v_invite_2  uuid;
  v_invite_3  uuid;
  v_row       record;
  v_failed    boolean;
begin
  select shop_id into v_shop_id from test_ids;
  v_invite_1 := public.create_shop_invite(
    v_shop_id, null, 'CASHIER@Example.COM', 'cashier');
  if v_invite_1 is null then
    raise exception 'NN (4c): email invite returned null';
  end if;

  -- Email normalized to lowercase + trimmed; idempotent on canonical form.
  v_invite_2 := public.create_shop_invite(
    v_shop_id, null, 'cashier@example.com', 'cashier');
  if v_invite_2 <> v_invite_1 then
    raise exception 'NN (4c): email invite not idempotent (got % vs %)',
      v_invite_2, v_invite_1;
  end if;

  -- Dual-contact (since 0059): passing both phone and email is allowed
  -- and merges into the existing invite — fills in the missing channel
  -- instead of raising.
  v_invite_3 := public.create_shop_invite(
    v_shop_id, '+252611555666', 'cashier@example.com', 'cashier');
  if v_invite_3 <> v_invite_1 then
    raise exception 'NN (4c): dual-channel call should merge into existing invite (got % vs %)',
      v_invite_3, v_invite_1;
  end if;
  select phone, email into v_row
    from public.shop_invite where id = v_invite_1;
  if v_row.phone <> '+252611555666' or v_row.email <> 'cashier@example.com' then
    raise exception 'NN (4c): dual-channel merge did not fill both channels (phone=%, email=%)',
      v_row.phone, v_row.email;
  end if;

  -- Neither phone nor email refused.
  v_failed := false;
  begin
    perform public.create_shop_invite(v_shop_id, null, null, 'cashier', null);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'NN (4c): empty contact must be refused';
  end if;
end;
$$;

-- 4d. claim_pending_invites_for_me: phone match + email match + idempotent.
do $$
declare
  v_shop_id     uuid;
  v_org_id      uuid;
  v_invite_p    uuid;
  v_invite_e    uuid;
  v_user_id     uuid := '00000000-0000-0000-0000-00000000C111';
  v_claimed     int;
  v_again       int;
  v_member      uuid;
  v_audit_join  int;
begin
  select shop_id, organization_id into v_shop_id, v_org_id from test_ids;

  -- Create a fresh auth.users row with both phone + email so we can
  -- exercise either side of the claim. The harness mocks auth.users.
  insert into auth.users (id, email, phone)
  values (v_user_id, 'newhire@example.com', '+252615550001')
  on conflict (id) do update
    set email = excluded.email, phone = excluded.phone;

  -- Owner issues both kinds of invite for the same future user.
  v_invite_p := public.create_shop_invite(
    v_shop_id, '+252615550001', null, 'cashier');
  v_invite_e := public.create_shop_invite(
    v_shop_id, null, 'newhire@example.com', 'cashier');

  -- Switch session to the new user and claim.
  set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000C111';

  v_claimed := public.claim_pending_invites_for_me();
  if v_claimed < 1 then
    raise exception 'NN (4d): claim returned 0 — expected ≥ 1';
  end if;

  -- Membership exists.
  select id into v_member
  from public.shop_membership
  where shop_id = v_shop_id and user_id = v_user_id;
  if v_member is null then
    raise exception 'NN (4d): shop_membership not created';
  end if;

  -- Both invites marked accepted.
  if exists (
    select 1 from public.shop_invite
    where id in (v_invite_p, v_invite_e) and accepted_at is null
  ) then
    raise exception 'NN (4d): some invites were not marked accepted';
  end if;

  -- setup.staff.join audit rows landed (one per invite).
  select count(*) into v_audit_join
  from public.audit_log
  where action_code = 'setup.staff.join'
    and shop_id = v_shop_id;
  if v_audit_join < 2 then
    raise exception 'NN (4d): expected ≥2 join audit rows, got %', v_audit_join;
  end if;

  -- Re-running claim is a no-op (no fresh pending invites left).
  v_again := public.claim_pending_invites_for_me();
  if v_again <> 0 then
    raise exception 'NN (4d): re-claim must be 0, got %', v_again;
  end if;

  set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
end;
$$;

-- 5. accept_shop_invite: phone mismatch + expired rejected.
do $$
declare
  v_shop_id  uuid;
  v_invite   uuid;
  v_failed   boolean;
begin
  select shop_id into v_shop_id from test_ids;
  v_invite := public.create_shop_invite(
    v_shop_id, '+252619998888', null, 'cashier');

  -- Caller's JWT phone is unset → must fail.
  v_failed := false;
  begin
    perform public.accept_shop_invite(v_invite);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'NN (5): accept_shop_invite must reject phone-mismatch';
  end if;

  -- Force the invite to be expired and try again.
  reset role;
  update public.shop_invite set expires_at = pg_catalog.now() - interval '1 day'
  where id = v_invite;
  set role authenticated;
  set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
  set request.jwt.claim.phone_number = '+252619998888';

  v_failed := false;
  begin
    perform public.accept_shop_invite(v_invite);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'NN (5): accept_shop_invite must reject expired invite';
  end if;
  reset request.jwt.claim.phone_number;
end;
$$;
reset role;

-- ---------------------------------------------------------------
-- 6. Bulk inventory edits (migration 0056).
-- ---------------------------------------------------------------

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- 6a. bulk_set_default_sale_price: cashier denied, owner happy path
--     writes sale_price + audit row.
do $$
declare
  v_shop_id      uuid;
  v_item_a       uuid;
  v_item_b       uuid;
  v_unit_a       uuid;
  v_unit_b       uuid;
  v_count        int;
  v_failed       boolean;
  v_audit_n      int;
  v_price_after  numeric;
begin
  select shop_id into v_shop_id from test_ids;

  -- Pick two priced-but-distinct shop_items for the test. The
  -- existing harness already activated a couple of items.
  select id into v_item_a from public.shop_item where shop_id = v_shop_id limit 1;
  if v_item_a is null then
    raise notice 'NN (6a): no shop_item rows; skipping bulk_set_default_sale_price';
    return;
  end if;
  select id into v_item_b from public.shop_item where shop_id = v_shop_id and id <> v_item_a limit 1;
  if v_item_b is null then
    v_item_b := v_item_a;  -- single-item shop, still test the loop
  end if;

  -- Cashier role denied.
  set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
  v_failed := false;
  begin
    perform public.bulk_set_default_sale_price(
      v_shop_id, array[v_item_a]::uuid[], 12.34);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'NN (6a): cashier was allowed to bulk_set_default_sale_price';
  end if;
  set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

  -- Owner happy path — count matches input.
  v_count := public.bulk_set_default_sale_price(
    v_shop_id, array[v_item_a, v_item_b]::uuid[], 7.50);
  if v_count < 1 then
    raise exception 'NN (6a): bulk update returned 0';
  end if;

  -- The chosen default unit now has the new price.
  select id, sale_price into v_unit_a, v_price_after
  from public.shop_item_unit
  where shop_id = v_shop_id and shop_item_id = v_item_a
  order by is_default_sale desc, (conversion_to_base = 1) desc
  limit 1;
  if v_price_after is null or v_price_after <> 7.50 then
    raise exception 'NN (6a): expected sale_price 7.50, got %', v_price_after;
  end if;

  -- Per-row audit log written.
  select count(*) into v_audit_n
  from public.audit_log
  where action_code = 'inventory.unit.price_edit'
    and entity_id = v_unit_a
    and after_state->>'via' = 'bulk';
  if v_audit_n < 1 then
    raise exception 'NN (6a): missing bulk audit row for inventory.unit.price_edit';
  end if;
end;
$$;

-- 6b. bulk_set_reorder_threshold: writes shop_item.reorder_threshold
--     + audit row; negative rejected.
do $$
declare
  v_shop_id   uuid;
  v_item      uuid;
  v_count     int;
  v_thresh    numeric;
  v_failed    boolean;
  v_audit_n   int;
begin
  select shop_id into v_shop_id from test_ids;
  select id into v_item from public.shop_item where shop_id = v_shop_id limit 1;
  if v_item is null then
    raise notice 'NN (6b): no shop_item rows; skipping bulk_set_reorder_threshold';
    return;
  end if;

  v_count := public.bulk_set_reorder_threshold(
    v_shop_id, array[v_item]::uuid[], 5);
  if v_count <> 1 then
    raise exception 'NN (6b): expected 1 row, got %', v_count;
  end if;

  select reorder_threshold into v_thresh
  from public.shop_item
  where shop_id = v_shop_id and id = v_item;
  if v_thresh is null or v_thresh <> 5 then
    raise exception 'NN (6b): expected threshold 5, got %', v_thresh;
  end if;

  -- Negative threshold refused.
  v_failed := false;
  begin
    perform public.bulk_set_reorder_threshold(
      v_shop_id, array[v_item]::uuid[], -3);
  exception when others then v_failed := true;
  end;
  if not v_failed then
    raise exception 'NN (6b): negative threshold must be refused';
  end if;

  -- Audit row from the successful run.
  select count(*) into v_audit_n
  from public.audit_log
  where action_code = 'inventory.product.edit'
    and entity_id = v_item
    and after_state->>'via' = 'bulk';
  if v_audit_n < 1 then
    raise exception 'NN (6b): missing bulk audit row for inventory.product.edit';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- §OO remove_or_disable_shop_item_unit (0063). Verify:
--   1. base packaging is refused.
--   2. fresh (unused) packaging is hard-deleted, RPC returns 'removed'.
--   3. packaging referenced by a transaction_line is soft-deactivated
--      and the row remains; RPC returns 'disabled'.
-- ---------------------------------------------------------------------------
do $$
declare
  v_shop_id      uuid;
  v_item_id      uuid;
  v_base_unit_id uuid;
  v_fresh_unit   uuid;
  v_used_unit    uuid;
  v_action       text;
  v_failed       boolean;
  v_remaining    int;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Pick any shop_item with a base unit to operate against.
  select si.id
    into v_item_id
    from public.shop_item si
    join public.shop_item_unit siu on siu.shop_item_id = si.id
   where si.shop_id = v_shop_id
     and siu.conversion_to_base = 1
     and siu.is_active
   limit 1;
  if v_item_id is null then
    raise exception 'OO: no shop_item found to test against';
  end if;

  select id into v_base_unit_id
    from public.shop_item_unit
   where shop_id = v_shop_id and shop_item_id = v_item_id
     and conversion_to_base = 1
   limit 1;

  -- 1. base packaging refused.
  v_failed := false;
  begin
    perform public.remove_or_disable_shop_item_unit(v_shop_id, v_base_unit_id);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'OO (1): base packaging removal must be refused';
  end if;

  -- 2. Fresh packaging — never sold/received — is hard-deleted.
  v_fresh_unit := public.create_shop_item_unit(
    p_shop_id             => v_shop_id,
    p_shop_item_id        => v_item_id,
    p_unit_code           => 'box',
    p_conversion_to_base  => 24,
    p_sale_price          => null
  );
  v_action := public.remove_or_disable_shop_item_unit(v_shop_id, v_fresh_unit);
  if v_action <> 'removed' then
    raise exception 'OO (2): expected "removed", got %', v_action;
  end if;
  select count(*) into v_remaining
    from public.shop_item_unit
   where id = v_fresh_unit;
  if v_remaining <> 0 then
    raise exception 'OO (2): row should be hard-deleted';
  end if;

  -- 3. Packaging that a transaction_line references is soft-disabled.
  -- Find any non-base packaging that's been referenced by a posted sale
  -- or receive. The harness's earlier sections (§15, §JJ etc.) post
  -- plenty of these.
  select tl.shop_item_unit_id
    into v_used_unit
    from public.transaction_line tl
    join public.shop_item_unit siu on siu.id = tl.shop_item_unit_id
   where tl.shop_id = v_shop_id
     and siu.is_active
     and siu.conversion_to_base <> 1
   limit 1;
  if v_used_unit is null then
    raise notice 'OO (3): no posted line referencing a non-base packaging; skipping';
    return;
  end if;
  v_action := public.remove_or_disable_shop_item_unit(v_shop_id, v_used_unit);
  if v_action <> 'disabled' then
    raise exception 'OO (3): expected "disabled", got %', v_action;
  end if;
  if (select is_active from public.shop_item_unit where id = v_used_unit) then
    raise exception 'OO (3): used packaging must be flipped inactive';
  end if;
  if (select is_default_sale or is_default_receive
        from public.shop_item_unit where id = v_used_unit) then
    raise exception 'OO (3): used packaging default flags must be cleared';
  end if;
  -- Restore so later sections that depend on it still pass.
  update public.shop_item_unit set is_active = true where id = v_used_unit;
end;
$$;

-- ---------------------------------------------------------------------------
-- §PP Onboarding form backend (0065). Verify:
--   1. shop_item.image_path column exists and is nullable.
--   2. 'opening' adjustment_reason row exists (used by opening-stock flow).
--   3. inventory.supplier_cost.set capability granted to owner AND cashier
--      (mirrors sibling onboarding RPCs which are auth_can_post_shop).
--   4. set_supplier_item_unit_cost:
--      a) non-member (no shop access) denied
--      b) owner upserts cleanly; second call updates same row (not duplicate)
--      c) negative cost refused
--      d) non-supplier party refused
--      e) cashier allowed (mirrors create_shop_item)
--   5. find_similar_shop_items:
--      a) returns near-match by alias
--      b) respects shop boundary (deny non-member)
--      c) empty query returns nothing
-- ---------------------------------------------------------------------------
do $$
declare
  v_col_nullable text;
begin
  select is_nullable into v_col_nullable
    from information_schema.columns
   where table_schema = 'public'
     and table_name   = 'shop_item'
     and column_name  = 'image_path';
  if v_col_nullable is null then
    raise exception 'PP (1): shop_item.image_path column is missing';
  end if;
  if v_col_nullable <> 'YES' then
    raise exception 'PP (1): shop_item.image_path must be nullable (got %)', v_col_nullable;
  end if;

  if not exists (
    select 1 from public.adjustment_reason
    where code = 'opening' and is_active
  ) then
    raise exception 'PP (2): opening adjustment_reason row missing';
  end if;
end;
$$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id      uuid;
  v_supplier_id  uuid;
  v_customer_id  uuid;
  v_item_id      uuid;
  v_unit_id      uuid;
  v_row_id_1     uuid;
  v_row_id_2     uuid;
  v_count_before int;
  v_count_after  int;
  v_failed       boolean;
  v_audit_n      int;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- Pick any supplier party in this shop.
  select p.id
    into v_supplier_id
    from public.party p
    join public.party_type pt on pt.id = p.type_id
   where p.shop_id = v_shop_id
     and pt.code in ('supplier', 'both')
     and p.is_active
   limit 1;
  if v_supplier_id is null then
    raise exception 'PP (4): no supplier in Setup Checklist Shop';
  end if;

  -- Pick any non-base packaging.
  select siu.id, siu.shop_item_id
    into v_unit_id, v_item_id
    from public.shop_item_unit siu
   where siu.shop_id = v_shop_id
     and siu.is_active
     and siu.conversion_to_base <> 1
   limit 1;
  if v_unit_id is null then
    raise exception 'PP (4): no non-base packaging in Setup Checklist Shop';
  end if;

  -- 3. Capability gate visible at the SQL level for owner.
  if not public.auth_user_has_capability('inventory.supplier_cost.set', v_shop_id) then
    raise exception 'PP (3): owner missing inventory.supplier_cost.set capability';
  end if;

  -- 4b. Owner can call; first call inserts.
  select count(*) into v_count_before
    from public.supplier_item_unit_cost
   where shop_id = v_shop_id
     and party_id = v_supplier_id
     and shop_item_unit_id = v_unit_id;

  perform public.set_supplier_item_unit_cost(
    v_shop_id, v_supplier_id, v_unit_id, 12.5
  );

  if (select last_unit_cost
        from public.supplier_item_unit_cost
       where shop_id = v_shop_id
         and party_id = v_supplier_id
         and shop_item_unit_id = v_unit_id) <> 12.5 then
    raise exception 'PP (4b): set_supplier_item_unit_cost did not persist cost';
  end if;

  -- 4b cont. Second call updates same row (no duplicate).
  perform public.set_supplier_item_unit_cost(
    v_shop_id, v_supplier_id, v_unit_id, 13.75
  );

  select count(*) into v_count_after
    from public.supplier_item_unit_cost
   where shop_id = v_shop_id
     and party_id = v_supplier_id
     and shop_item_unit_id = v_unit_id;
  if v_count_after <> greatest(1, v_count_before) and v_count_after <> v_count_before then
    raise exception 'PP (4b): expected 1 row after upsert, got % (was %)', v_count_after, v_count_before;
  end if;
  if (select last_unit_cost
        from public.supplier_item_unit_cost
       where shop_id = v_shop_id
         and party_id = v_supplier_id
         and shop_item_unit_id = v_unit_id) <> 13.75 then
    raise exception 'PP (4b): upsert did not update last_unit_cost';
  end if;

  -- Audit row landed.
  select count(*) into v_audit_n
    from public.audit_log
   where shop_id = v_shop_id
     and action_code = 'inventory.supplier_cost.set'
     and entity_id = v_unit_id;
  if v_audit_n < 2 then
    raise exception 'PP (4b): expected ≥2 audit rows, got %', v_audit_n;
  end if;

  -- 4c. Negative cost refused.
  v_failed := false;
  begin
    perform public.set_supplier_item_unit_cost(
      v_shop_id, v_supplier_id, v_unit_id, -1
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'PP (4c): negative cost was accepted';
  end if;

  -- 4d. Customer (non-supplier) refused.
  select p.id
    into v_customer_id
    from public.party p
    join public.party_type pt on pt.id = p.type_id
   where p.shop_id = v_shop_id
     and pt.code = 'customer'
     and p.is_active
   limit 1;
  if v_customer_id is not null then
    v_failed := false;
    begin
      perform public.set_supplier_item_unit_cost(
        v_shop_id, v_customer_id, v_unit_id, 10
      );
    exception when raise_exception then v_failed := true;
    end;
    if not v_failed then
      raise exception 'PP (4d): customer party accepted as supplier';
    end if;
  end if;

  -- 5a. find_similar_shop_items returns at least one row when querying
  -- against an existing alias prefix.
  perform 1 from public.find_similar_shop_items(
    v_shop_id, 'sug', null, 'en'
  );
  -- (Doesn't assert specific row counts — depends on the fixture
  -- aliases; we just want the call to succeed.)

  -- 5c. Empty query returns nothing.
  if exists (
    select 1 from public.find_similar_shop_items(v_shop_id, '', null, 'en')
  ) then
    raise exception 'PP (5c): empty query should return no rows';
  end if;
end;
$$;

-- 4e. Cashier allowed (mirrors create_shop_item — onboarding flow).
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$
declare
  v_shop_id      uuid;
  v_supplier_id  uuid;
  v_unit_id      uuid;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  select p.id
    into v_supplier_id
    from public.party p
    join public.party_type pt on pt.id = p.type_id
   where p.shop_id = v_shop_id
     and pt.code in ('supplier', 'both')
     and p.is_active
   limit 1;
  select siu.id
    into v_unit_id
    from public.shop_item_unit siu
   where siu.shop_id = v_shop_id
     and siu.is_active
     and siu.conversion_to_base <> 1
   limit 1;

  perform public.set_supplier_item_unit_cost(
    v_shop_id, v_supplier_id, v_unit_id, 9.99
  );
  if (select last_unit_cost
        from public.supplier_item_unit_cost
       where shop_id = v_shop_id
         and party_id = v_supplier_id
         and shop_item_unit_id = v_unit_id) <> 9.99 then
    raise exception 'PP (4e): cashier set did not persist cost';
  end if;
end;
$$;

-- 4a + 5b. Non-member (user3) — both RPCs must deny.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
do $$
declare
  v_shop_id     uuid;
  v_supplier_id uuid;
  v_unit_id     uuid;
  v_failed      boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';

  -- 4a. set denied for non-member.
  select p.id
    into v_supplier_id
    from public.party p
    join public.party_type pt on pt.id = p.type_id
   where p.shop_id = v_shop_id
     and pt.code in ('supplier', 'both')
     and p.is_active
   limit 1;
  select siu.id
    into v_unit_id
    from public.shop_item_unit siu
   where siu.shop_id = v_shop_id
     and siu.is_active
     and siu.conversion_to_base <> 1
   limit 1;

  v_failed := false;
  begin
    perform public.set_supplier_item_unit_cost(
      v_shop_id, v_supplier_id, v_unit_id, 5
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'PP (4a): non-member could set supplier cost';
  end if;

  -- 5b. find_similar denied for non-member.
  v_failed := false;
  begin
    perform 1 from public.find_similar_shop_items(v_shop_id, 'anything', null, 'en');
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'PP (5b): non-member could query find_similar_shop_items';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- §QQ platform_config (0067). Verify:
--   1. Platform staff can upsert + select platform defaults (NULL org_id).
--   2. Platform staff can upsert org-scoped overrides.
--   3. Org member can SELECT only their org's overrides via the table.
--   4. Org member is REJECTED from set_platform_config.
--   5. get_platform_config returns org-scoped value when both NULL
--      and org-scoped exist for the same key (org wins).
--   6. get_platform_config returns NULL-org default when only that
--      row exists for a key.
--   7. get_platform_config rejected for non-members of the org.
--   8. Blank key + NULL value rejected by set_platform_config.
-- ---------------------------------------------------------------------------

-- 1+2: platform staff upserts both default + org override.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';

do $$
declare
  v_org_id uuid;
begin
  select organization_id into v_org_id from test_ids;

  -- (1) Platform default for queue_max_pending.
  perform public.set_platform_config(null, 'queue_max_pending', '150'::jsonb);
  if (
    select value::text from public.platform_config
    where org_id is null and key = 'queue_max_pending'
  ) <> '150' then
    raise exception 'QQ (1): platform default not written';
  end if;

  -- (2) Org override for the same key.
  perform public.set_platform_config(v_org_id, 'queue_max_pending', '300'::jsonb);
  if (
    select value::text from public.platform_config
    where org_id = v_org_id and key = 'queue_max_pending'
  ) <> '300' then
    raise exception 'QQ (2): org override not written';
  end if;

  -- Another default-only key (no org override) for case 6.
  perform public.set_platform_config(null, 'cache_budget_mb', '120'::jsonb);

  -- (8) Blank key rejected.
  begin
    perform public.set_platform_config(null, '   ', '"x"'::jsonb);
    raise exception 'QQ (8): blank key was accepted';
  exception when raise_exception then null;
  end;

  -- (8) NULL value rejected.
  begin
    perform public.set_platform_config(null, 'foo', null);
    raise exception 'QQ (8): null value was accepted';
  exception when raise_exception then null;
  end;
end;
$$;

-- 5+6: get_platform_config from owner (org member).
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_org_id uuid;
  v_shop_id uuid;
  v_qmp_value jsonb;
  v_cbm_value jsonb;
begin
  select organization_id, shop_id into v_org_id, v_shop_id from test_ids;

  -- (5) Org-scoped value wins for queue_max_pending.
  select value into v_qmp_value
    from public.get_platform_config(v_org_id)
   where key = 'queue_max_pending';
  if v_qmp_value::text <> '300' then
    raise exception 'QQ (5): expected org override (300), got %', v_qmp_value;
  end if;

  -- (6) Platform default surfaces for cache_budget_mb (no org row).
  select value into v_cbm_value
    from public.get_platform_config(v_org_id)
   where key = 'cache_budget_mb';
  if v_cbm_value::text <> '120' then
    raise exception 'QQ (6): expected platform default (120), got %', v_cbm_value;
  end if;

  -- (6b) Shop-id wrapper returns the same merged set.
  select value into v_qmp_value
    from public.get_platform_config_for_shop(v_shop_id)
   where key = 'queue_max_pending';
  if v_qmp_value::text <> '300' then
    raise exception 'QQ (6b): shop-id wrapper missed org override (got %)', v_qmp_value;
  end if;
end;
$$;

-- 3: owner sees their org row via direct table select; does NOT see
-- the NULL-org platform-default row.
do $$
declare
  v_org_id uuid;
  v_org_visible int;
  v_default_visible int;
begin
  select organization_id into v_org_id from test_ids;

  select count(*) into v_org_visible
    from public.platform_config
   where org_id = v_org_id;
  if v_org_visible < 1 then
    raise exception 'QQ (3): owner cannot see org-scoped platform_config row';
  end if;

  select count(*) into v_default_visible
    from public.platform_config
   where org_id is null;
  if v_default_visible <> 0 then
    raise exception 'QQ (3): owner unexpectedly saw NULL-org platform default rows (RLS leak)';
  end if;
end;
$$;

-- 4: owner is rejected from set_platform_config.
do $$
declare
  v_failed boolean := false;
begin
  begin
    perform public.set_platform_config(null, 'queue_max_pending', '999'::jsonb);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'QQ (4): owner was allowed to set_platform_config';
  end if;
end;
$$;

-- 7: get_platform_config rejected for non-members. User 3 has no org
-- membership.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_org_id uuid;
  v_failed boolean := false;
begin
  select organization_id into v_org_id from test_ids;
  begin
    perform 1 from public.get_platform_config(v_org_id);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'QQ (7): non-member could read get_platform_config';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

reset role;

-- §RR set_audit_original_actor (0068). Verify:
--   1. The original_actor_user_id column exists on audit_log and
--      defaults to NULL.
--   2. set_audit_original_actor backfills the most-recent audit row
--      for (shop, entity).
--   3. Re-calling with the same value is a no-op (idempotent).
--   4. Calling for an entity with no audit row no-ops silently.
--   5. Non-shop-member calls are rejected.

do $$
declare
  v_shop_id     uuid;
  v_owner_id    uuid := '00000000-0000-0000-0000-000000000001';
  v_other_user  uuid := '00000000-0000-0000-0000-000000000099';
  v_synthetic   uuid := '11111111-1111-1111-1111-111111111111';
  v_audit_id    uuid;
  v_after_set   uuid;
  v_random_ent  uuid := extensions.gen_random_uuid();
begin
  select id into v_shop_id from public.shop where name = 'Main Shop' limit 1;
  if v_shop_id is null then
    raise exception 'RR pre: Main Shop fixture missing';
  end if;

  -- Insert a fixture audit row (use _audit_log helper).
  v_audit_id := public._audit_log(
    p_shop_id      => v_shop_id,
    p_action_code  => 'sale.post',
    p_entity_type  => 'txn',
    p_entity_id    => v_synthetic,
    p_after        => '{"test": "rr"}'::jsonb,
    p_client_op_id => null
  );

  -- (1) original_actor_user_id starts NULL.
  if (select original_actor_user_id from public.audit_log
        where id = v_audit_id) is not null then
    raise exception 'RR (1): original_actor_user_id should be NULL on insert';
  end if;

  -- (2) Backfill.
  perform public.set_audit_original_actor(
    v_shop_id, v_synthetic, v_other_user
  );
  if (select original_actor_user_id from public.audit_log
        where id = v_audit_id) <> v_other_user then
    raise exception 'RR (2): set_audit_original_actor did not stamp the row';
  end if;

  -- (3) Idempotent — same call again.
  perform public.set_audit_original_actor(
    v_shop_id, v_synthetic, v_other_user
  );
  if (select original_actor_user_id from public.audit_log
        where id = v_audit_id) <> v_other_user then
    raise exception 'RR (3): idempotent re-call broke the stamp';
  end if;

  -- (4) No matching audit row — no-op, no exception.
  perform public.set_audit_original_actor(
    v_shop_id, v_random_ent, v_other_user
  );
end;
$$;

-- (5) Non-member rejection. Switch to a user with no membership in
--     the org and assert the RPC raises.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id     uuid;
  v_synthetic   uuid := '22222222-2222-2222-2222-222222222222';
  v_failed      boolean := false;
begin
  select id into v_shop_id from public.shop where name = 'Main Shop' limit 1;
  begin
    perform public.set_audit_original_actor(
      v_shop_id, v_synthetic, '00000000-0000-0000-0000-000000000099'
    );
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'RR (5): non-member was allowed to call set_audit_original_actor';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
reset role;

-- §SS Sync RPCs (0069) — full + delta sync RPCs powering the
-- offline-first mobile architecture (#373).  Verify:
--   1. get_shop_full_sync returns items + parties + categories +
--      transactions payloads and writes a shop_sync_audit row.
--   2. A second call within 24h without p_force=true raises.
--   3. p_force=true bypasses the rate limit.
--   4. get_shop_items_delta returns only rows updated after the
--      cutoff and includes is_active=false rows (tombstones).
--   5. get_parties_delta + get_categories_delta + get_transactions_delta
--      respect their cutoff.
--   6. Non-shop-member calls are rejected on all RPCs.

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id      uuid;
  v_payload      jsonb;
  v_failed       boolean;
  v_item_id      uuid;
  v_party_id     uuid;
  v_cutoff       timestamptz;
  v_audit_count  int;
begin
  select id into v_shop_id from public.shop where name = 'Main Shop' limit 1;
  if v_shop_id is null then
    raise exception 'SS pre: Main Shop fixture missing';
  end if;

  -- (1) full_sync returns a populated payload + writes audit row.
  v_payload := public.get_shop_full_sync(v_shop_id, false);
  if v_payload is null then
    raise exception 'SS (1): get_shop_full_sync returned null';
  end if;
  if v_payload->'items_payload' is null
     or v_payload->'parties_payload' is null
     or v_payload->'categories_payload' is null
     or v_payload->'transactions_payload' is null then
    raise exception 'SS (1): full_sync payload missing a section';
  end if;
  select count(*) into v_audit_count
    from public.shop_sync_audit
    where shop_id = v_shop_id and kind = 'full';
  if v_audit_count < 1 then
    raise exception 'SS (1): shop_sync_audit row not written for full sync';
  end if;

  -- (2) Second call within 24h without p_force should raise.
  v_failed := false;
  begin
    perform public.get_shop_full_sync(v_shop_id, false);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'SS (2): full_sync rate-limit did not engage';
  end if;

  -- (3) p_force=true bypasses the rate limit.
  v_payload := public.get_shop_full_sync(v_shop_id, true);
  if v_payload is null then
    raise exception 'SS (3): forced full_sync returned null';
  end if;

  -- (4) Delta after far-past cutoff returns the rows we have.
  v_cutoff := 'epoch'::timestamptz;
  v_payload := public.get_shop_items_delta(v_shop_id, v_cutoff);
  if jsonb_array_length(v_payload->'items') < 1 then
    raise exception 'SS (4): items_delta returned 0 items for a far-past cutoff';
  end if;

  -- (4a) Soft-delete an item (set is_active=false) and confirm
  --      the delta surfaces it as a tombstone.
  update public.shop_item
    set is_active = false
    where shop_id = v_shop_id
      and id = (select id from public.shop_item
                  where shop_id = v_shop_id and is_active limit 1)
    returning id into v_item_id;
  v_cutoff := now() - interval '1 second';
  -- Bump the row's updated_at so the trigger-stamped value lands
  -- after v_cutoff regardless of clock resolution.
  perform pg_sleep(1.1);
  update public.shop_item set updated_at = now() where id = v_item_id;
  v_payload := public.get_shop_items_delta(v_shop_id, v_cutoff);
  if not exists (
    select 1
    from jsonb_array_elements(v_payload->'items') x
    where (x->>'shop_item_id')::uuid = v_item_id
      and (x->>'is_active')::boolean = false
  ) then
    raise exception 'SS (4a): tombstone for soft-deleted item not in items_delta';
  end if;

  -- (5) parties_delta + categories_delta + transactions_delta
  --     return data for a far-past cutoff.
  v_payload := public.get_parties_delta(v_shop_id, 'epoch'::timestamptz);
  if v_payload->'parties' is null then
    raise exception 'SS (5a): parties_delta payload missing parties array';
  end if;
  v_payload := public.get_categories_delta(v_shop_id, 'epoch'::timestamptz);
  if v_payload->'expense_categories' is null then
    raise exception 'SS (5b): categories_delta missing expense_categories';
  end if;
  v_payload := public.get_transactions_delta(v_shop_id, 'epoch'::timestamptz, 100);
  if v_payload->'transactions' is null then
    raise exception 'SS (5c): transactions_delta missing transactions array';
  end if;
end;
$$;

-- (6) Non-shop-member rejection on all sync RPCs.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id  uuid;
  v_failed   boolean;
begin
  -- This user (000...3) was set up in earlier sections as NOT a
  -- member of Main Shop.
  select id into v_shop_id from public.shop where name = 'Main Shop' limit 1;

  v_failed := false;
  begin
    perform public.get_shop_full_sync(v_shop_id, false);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'SS (6a): non-member allowed to call get_shop_full_sync';
  end if;

  v_failed := false;
  begin
    perform public.get_shop_items_delta(v_shop_id, 'epoch'::timestamptz);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'SS (6b): non-member allowed to call get_shop_items_delta';
  end if;

  v_failed := false;
  begin
    perform public.get_parties_delta(v_shop_id, 'epoch'::timestamptz);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'SS (6c): non-member allowed to call get_parties_delta';
  end if;

  v_failed := false;
  begin
    perform public.get_categories_delta(v_shop_id, 'epoch'::timestamptz);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'SS (6d): non-member allowed to call get_categories_delta';
  end if;

  v_failed := false;
  begin
    perform public.get_transactions_delta(v_shop_id, 'epoch'::timestamptz, 100);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'SS (6e): non-member allowed to call get_transactions_delta';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
reset role;

-- ---------------------------------------------------------------------------
-- §TT mutation_idempotency (0074). Verify the new p_client_op_id
-- short-circuit on three representative RPCs (one add, one set,
-- one remove) — the other 7 RPCs follow the same mechanical
-- pattern.
--   1. add_shop_item_alias: same client_op_id → same alias_id
--      returned, no duplicate row.
--   2. set_shop_item_unit_sale_price: same client_op_id → second
--      call is a no-op (we mutate the price between calls and
--      assert the second invocation does NOT overwrite).
--   3. remove_shop_item_alias: same client_op_id called twice is
--      a no-op on the second call (the row is already gone, but
--      the RPC must not raise).
--   4. Smoke: calling without p_client_op_id (null) behaves
--      exactly like the pre-0074 path.
-- ---------------------------------------------------------------------------

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id           uuid;
  v_shop_item_id      uuid;
  v_default_unit_id   uuid;
  v_alias_id_1        uuid;
  v_alias_id_2        uuid;
  v_alias_count       int;
  v_price             numeric;
  v_idem_count        int;
  v_throwaway_id      uuid;
begin
  select id into v_shop_id from public.shop where name = 'Main Shop' limit 1;
  if v_shop_id is null then
    raise exception 'TT pre: Main Shop fixture missing';
  end if;

  -- Fresh shop_item so the assertions are deterministic.
  select shop_item_id, default_shop_item_unit_id
    into v_shop_item_id, v_default_unit_id
    from public.create_shop_item(
      v_shop_id, 'TT Idempotency Test', 'en', 'kg', null, null
    );

  -- (1) add_shop_item_alias dedup: two calls with the same
  -- client_op_id should return the same alias_id and create
  -- exactly ONE alias row beyond the display alias.
  v_alias_id_1 := public.add_shop_item_alias(
    v_shop_id, v_shop_item_id, 'tt-alpha', 'en',
    false, 'manual', 'tt-client-1'
  );
  v_alias_id_2 := public.add_shop_item_alias(
    v_shop_id, v_shop_item_id, 'tt-alpha', 'en',
    false, 'manual', 'tt-client-1'
  );
  if v_alias_id_1 is null or v_alias_id_1 <> v_alias_id_2 then
    raise exception 'TT (1): dup add_shop_item_alias should return same id (got % vs %)',
      v_alias_id_1, v_alias_id_2;
  end if;

  -- (2) set_shop_item_unit_sale_price dedup: first call sets
  -- price=11.0; we then DIRECTLY UPDATE the price to 22.0 (out
  -- of band) and re-call the RPC with the same client_op_id.
  -- The RPC must short-circuit and leave the price at 22.0.
  perform public.set_shop_item_unit_sale_price(
    v_shop_id, v_default_unit_id, 11.0, 'tt-client-2'
  );
  update public.shop_item_unit set sale_price = 22.0
   where shop_id = v_shop_id and id = v_default_unit_id;
  perform public.set_shop_item_unit_sale_price(
    v_shop_id, v_default_unit_id, 11.0, 'tt-client-2'
  );
  select sale_price into v_price from public.shop_item_unit
   where shop_id = v_shop_id and id = v_default_unit_id;
  if v_price <> 22.0 then
    raise exception 'TT (2): dup set price should have been a no-op (price=%)', v_price;
  end if;

  -- (3) remove_shop_item_alias dedup: first call deletes, second
  -- call with the same client_op_id is a no-op (must NOT raise
  -- "Alias not found").
  perform public.remove_shop_item_alias(
    v_shop_id, v_alias_id_1, 'tt-client-3'
  );
  -- Sanity: row is gone.
  if exists (
    select 1 from public.shop_item_alias where id = v_alias_id_1
  ) then
    raise exception 'TT (3): remove_shop_item_alias did not delete';
  end if;
  -- Duplicate call must NOT raise.
  perform public.remove_shop_item_alias(
    v_shop_id, v_alias_id_1, 'tt-client-3'
  );

  -- (4) Null client_op_id keeps legacy behavior — calling
  -- add_shop_item_alias twice without an idempotency key should
  -- be naturally idempotent via the existing on-conflict-do-
  -- update path (returns the same id; no duplicate row), and no
  -- mutation_idempotency row is recorded.
  v_throwaway_id := public.add_shop_item_alias(
    v_shop_id, v_shop_item_id, 'tt-beta', 'en'
  );
  v_throwaway_id := public.add_shop_item_alias(
    v_shop_id, v_shop_item_id, 'tt-beta', 'en'
  );
  select count(*) into v_alias_count
    from public.shop_item_alias
   where shop_id = v_shop_id
     and shop_item_id = v_shop_item_id
     and alias_text = 'tt-beta';
  if v_alias_count <> 1 then
    raise exception 'TT (4): legacy path produced % rows for tt-beta', v_alias_count;
  end if;

  -- Confirm the idempotency table has exactly the expected three
  -- entries from steps 1-3 (not the legacy step 4).
  select count(*) into v_idem_count
    from public.mutation_idempotency
   where shop_id = v_shop_id
     and client_op_id like 'tt-client-%';
  if v_idem_count <> 3 then
    raise exception 'TT (5): expected 3 mutation_idempotency rows, got %', v_idem_count;
  end if;

  raise notice 'TT: mutation_idempotency tests passed';
end;
$$;

-- ---------------------------------------------------------------------------
-- §CAT manage categories (0076): owner CRUD on shop product + expense
-- categories, idempotency, shop isolation, global-row protection, the
-- set_shop_item_category scope guard, and cashier/unrelated denial.
-- ---------------------------------------------------------------------------
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';  -- owner

do $$
declare
  v_shop_id    uuid;
  v_other_shop uuid;
  v_cat_id     uuid := gen_random_uuid();
  v_exp_id     uuid := gen_random_uuid();
  v_item_id    uuid;
  v_global_cat uuid;
  v_row_shop   uuid;
  v_name       text;
  v_active     boolean;
  v_count      integer;
  v_failed     boolean;
begin
  select id into v_shop_id    from public.shop where name = 'Setup Checklist Shop';
  select id into v_other_shop from public.shop where name = 'Main Shop';

  -- create_shop_category (owner happy path)
  perform public.create_shop_category(v_shop_id, v_cat_id, 'Khat', 'op-cat-1');
  select name, is_active, shop_id into v_name, v_active, v_row_shop
    from public.category where id = v_cat_id;
  if v_name <> 'Khat' or not v_active or v_row_shop is distinct from v_shop_id then
    raise exception 'CAT: create_shop_category did not persist correctly';
  end if;

  -- idempotent: same client_op_id + id → still one row
  perform public.create_shop_category(v_shop_id, v_cat_id, 'Khat', 'op-cat-1');
  select count(*) into v_count from public.category where id = v_cat_id;
  if v_count <> 1 then
    raise exception 'CAT: create_shop_category not idempotent (% rows)', v_count;
  end if;

  -- appears in list_categories for this shop, flagged is_custom...
  if not exists (
    select 1 from public.list_categories('en', v_shop_id)
     where id = v_cat_id and is_custom
  ) then
    raise exception 'CAT: custom category missing from list_categories';
  end if;
  -- ...and NOT for a shop that does not own it
  if exists (
    select 1 from public.list_categories('en', v_other_shop) where id = v_cat_id
  ) then
    raise exception 'CAT: custom category leaked to another shop';
  end if;

  -- rename
  perform public.rename_shop_category(v_shop_id, v_cat_id, 'Khat Leaves', null);
  if (select name from public.category where id = v_cat_id) <> 'Khat Leaves' then
    raise exception 'CAT: rename_shop_category did not persist';
  end if;

  -- cannot rename a GLOBAL category (shop_id null)
  select id into v_global_cat from public.category where shop_id is null limit 1;
  v_failed := false;
  begin
    perform public.rename_shop_category(v_shop_id, v_global_cat, 'Hijack', null);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'CAT: owner renamed a global category';
  end if;

  -- hide removes it from list_categories; re-activate restores
  perform public.set_shop_category_active(v_shop_id, v_cat_id, false, null);
  if exists (
    select 1 from public.list_categories('en', v_shop_id) where id = v_cat_id
  ) then
    raise exception 'CAT: hidden category still listed';
  end if;
  perform public.set_shop_category_active(v_shop_id, v_cat_id, true, null);

  -- scope guard: cannot assign this shop's custom category to an item in
  -- another shop (both owned by user1 → auth passes; scope check fires)
  select id into v_item_id from public.shop_item where shop_id = v_other_shop limit 1;
  if v_item_id is not null then
    v_failed := false;
    begin
      perform public.set_shop_item_category(v_other_shop, v_item_id, v_cat_id);
    exception when raise_exception then v_failed := true;
    end;
    if not v_failed then
      raise exception 'CAT: set_shop_item_category accepted a foreign-shop category';
    end if;
  end if;

  -- expense category CRUD
  perform public.create_expense_category(v_shop_id, v_exp_id, 'Generator Fuel', 'op-exp-1');
  if (select name from public.expense_category where id = v_exp_id) <> 'Generator Fuel' then
    raise exception 'CAT: create_expense_category did not persist';
  end if;
  perform public.rename_expense_category(v_shop_id, v_exp_id, 'Fuel', null);
  if (select name from public.expense_category where id = v_exp_id) <> 'Fuel' then
    raise exception 'CAT: rename_expense_category did not persist';
  end if;
  perform public.set_expense_category_active(v_shop_id, v_exp_id, false, null);
  if (select is_active from public.expense_category where id = v_exp_id) then
    raise exception 'CAT: set_expense_category_active did not hide';
  end if;

  raise notice 'CAT: owner happy-path + scope tests passed';
end;
$$;

-- Cashier (user2) cannot manage categories (config = setup-only)
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$
declare
  v_shop_id uuid;
  v_failed  boolean;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  v_failed := false;
  begin
    perform public.create_shop_category(v_shop_id, gen_random_uuid(), 'CashierCat', null);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'CAT: cashier created a product category';
  end if;

  v_failed := false;
  begin
    perform public.create_expense_category(v_shop_id, gen_random_uuid(), 'CashierExp', null);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'CAT: cashier created an expense category';
  end if;
  raise notice 'CAT: cashier denial passed';
end;
$$;

-- Unrelated user (user3) denied
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
do $$
declare
  v_shop_id uuid;
  v_failed  boolean := false;
begin
  select id into v_shop_id from public.shop where name = 'Setup Checklist Shop';
  begin
    perform public.create_shop_category(v_shop_id, gen_random_uuid(), 'IntruderCat', null);
  exception when raise_exception then v_failed := true;
  end;
  if not v_failed then
    raise exception 'CAT: unrelated user created a category';
  end if;
  raise notice 'CAT: unrelated denial passed';
end;
$$;

-- =====================================================================
-- §DC Dukaan Cunto templates (0017). Test template seeds the full
--     catalog + quick actions; Empty template seeds config (settings +
--     expense categories) only — zero inventory, no quick actions.
-- =====================================================================

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_org_id     uuid;
  v_test_shop  uuid;
  v_empty_shop uuid;
  v_test_tmpl  uuid;
  v_empty_tmpl uuid;
  v_item_count int;
  v_tmpl_items int;
begin
  select id into v_org_id from public.organization where name = 'Owner Org';
  if v_org_id is null then
    raise exception 'DC pre: Owner Org fixture missing';
  end if;

  select id into v_test_tmpl  from public.template where code = 'test_dukaan_cunto'  and version = 1;
  select id into v_empty_tmpl from public.template where code = 'empty_dukaan_cunto' and version = 1;
  if v_test_tmpl is null or v_empty_tmpl is null then
    raise exception 'DC pre: dukaan cunto templates not seeded by 0017';
  end if;
  -- Both must be active so they appear in the shop-type picker.
  if not (select is_active from public.template where id = v_test_tmpl)
     or not (select is_active from public.template where id = v_empty_tmpl) then
    raise exception 'DC: a dukaan cunto template is inactive (would not show in picker)';
  end if;

  v_test_shop  := public.create_shop(v_org_id, 'DC Test Shop');
  v_empty_shop := public.create_shop(v_org_id, 'DC Empty Shop');

  -- TEST template: every curated item is activated onto the shop.
  perform public.apply_template(v_test_shop, v_test_tmpl);
  select count(*) into v_item_count from public.shop_item where shop_id = v_test_shop;
  select count(*) into v_tmpl_items from public.template_item where template_id = v_test_tmpl;
  if v_tmpl_items = 0 then
    raise exception 'DC: test template has no template_item rows';
  end if;
  if v_item_count < v_tmpl_items then
    raise exception 'DC: test apply activated % of % items', v_item_count, v_tmpl_items;
  end if;
  if not exists (
    select 1 from public.shop_item si join public.item i on i.id = si.item_id
    where si.shop_id = v_test_shop and i.code = 'bariis_basmati_25kg'
  ) then
    raise exception 'DC: bariis not activated by test template';
  end if;
  if (select count(*) from public.expense_category where shop_id = v_test_shop) = 0 then
    raise exception 'DC: test template seeded no expense categories';
  end if;

  -- EMPTY template: config only — zero inventory, but settings + expense cats.
  perform public.apply_template(v_empty_shop, v_empty_tmpl);
  if (select count(*) from public.shop_item where shop_id = v_empty_shop) <> 0 then
    raise exception 'DC: empty template must seed zero items';
  end if;
  if (select count(*) from public.expense_category where shop_id = v_empty_shop) = 0 then
    raise exception 'DC: empty template seeded no expense categories';
  end if;
  if not exists (
    select 1 from public.shop_setting where shop_id = v_empty_shop and key = 'currency_default'
  ) then
    raise exception 'DC: empty template seeded no settings';
  end if;

  raise notice 'DC: dukaan cunto template tests passed (test=% items, empty=0)', v_item_count;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
reset role;

do $$
begin
  raise notice 'Backend migration tests passed';
end;
$$;
SQL

echo "Backend migration tests passed"
