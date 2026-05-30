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
create table auth.users (
  id uuid primary key default gen_random_uuid()
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
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to authenticated, anon;
grant select on auth.users to authenticated, anon;
grant usage on schema storage to authenticated, anon;
SQL

for migration in "$ROOT_DIR"/supabase/migrations/*.sql; do
  echo "Applying $(basename "$migration")"
  docker exec -i "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -d postgres < "$migration" >/dev/null
done

docker exec -i "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -d postgres <<'SQL'
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
end;
$$;

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
  v_org_id uuid;
  v_shop_id uuid;
  v_second_shop_id uuid;
  v_cashier_role_id uuid;
begin
  select organization_id, shop_id, second_shop_id
  into v_org_id, v_shop_id, v_second_shop_id
  from test_ids;

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

create temp table transaction_test_ids as
select
  t.shop_id,
  i.id as item_id,
  u.id as piece_unit_id
from test_ids t
join public.item i on i.shop_id = t.shop_id and i.code = 'candy'
cross join public.unit u
where u.code = 'piece';

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

do $$
declare
  v_shop_id uuid;
  v_second_shop_id uuid;
  v_unit_id uuid;
begin
  select shop_id, second_shop_id into v_shop_id, v_second_shop_id from test_ids;
  select id into v_unit_id from public.unit where code = 'piece';

  if (select count(*) from public.shop) <> 1 then
    raise exception 'cashier should see exactly one assigned shop';
  end if;

  if exists (select 1 from public.shop where id = v_second_shop_id) then
    raise exception 'cashier can see unassigned shop';
  end if;

  begin
    insert into public.item (
      shop_id,
      code,
      name,
      base_unit_id,
      default_sale_unit_id,
      default_receive_unit_id
    )
    values (v_shop_id, 'cashier_item', 'Cashier Item', v_unit_id, v_unit_id, v_unit_id);
    raise exception 'cashier inserted setup item';
  exception
    when insufficient_privilege or check_violation or with_check_option_violation then
      null;
  end;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';

do $$
declare
  v_concept_id uuid;
  v_catalog_item_id uuid;
  v_revision_id uuid;
  v_template_id uuid;
begin
  insert into public.catalog_product_concept (code, name_en)
  values ('sugar', 'Sugar')
  returning id into v_concept_id;

  insert into public.catalog_item (concept_id, code)
  values (v_concept_id, 'sugar_generic_bag')
  returning id into v_catalog_item_id;

  insert into public.catalog_item_revision (
    catalog_item_id,
    revision_number,
    name,
    category_code,
    base_unit_code,
    default_sale_unit_code,
    default_receive_unit_code,
    suggested_sale_price,
    reorder_threshold
  )
  values (
    v_catalog_item_id,
    1,
    'Sugar Bag',
    'grocery',
    'bag',
    'bag',
    'bag',
    10,
    2
  )
  returning id into v_revision_id;

  insert into public.catalog_item_unit (
    catalog_item_id,
    revision_id,
    unit_code,
    conversion_to_base,
    is_base_unit,
    allow_sale,
    allow_receive
  )
  values (v_catalog_item_id, v_revision_id, 'bag', 1, true, true, true);

  insert into public.catalog_item_alias (catalog_item_id, language_code, alias_text)
  values (v_catalog_item_id, 'en', 'white sugar');

  update public.catalog_item
  set current_revision_id = v_revision_id
  where id = v_catalog_item_id;

  insert into public.template (
    code,
    kind,
    name,
    locale_default,
    currency_default,
    version,
    is_active
  )
  values ('grocery_v1', 'shop_starter', 'Grocery V1', 'en', 'USD', 1, true)
  returning id into v_template_id;

  insert into public.template_pack (template_id, code, version, is_required, file_path)
  values
    (v_template_id, 'core', 1, true, 'templates/grocery/core.json'),
    (v_template_id, 'drinks', 1, false, 'templates/grocery/drinks.json');

  insert into public.template_setting (template_id, key, value)
  values (v_template_id, 'negative_stock_policy', '"warn"');

  insert into public.template_expense_category (template_id, code, name, name_translations)
  values (v_template_id, 'rent', 'Rent', '{"so": "Kiro"}');

  insert into public.template_supplier_type (template_id, supplier_type_code, label)
  values (v_template_id, 'wholesaler', '{"en": "Wholesaler", "so": "Jumlo"}');

  insert into public.template_item (
    template_id,
    item_code,
    catalog_item_id,
    catalog_revision_id,
    suggested_sale_price_override,
    reorder_threshold_override
  )
  values (
    v_template_id,
    'sugar_generic_bag',
    v_catalog_item_id,
    v_revision_id,
    9.75,
    3
  );

  insert into public.template_quantity_suggestion (template_id, item_code, context, unit_code, quantity, sort_order)
  values
    (v_template_id, 'sugar_generic_bag', 'sale', 'bag', 1, 1),
    (v_template_id, 'sugar_generic_bag', 'receive', 'bag', 1, 1);

  insert into public.template_quick_action (template_id, screen, position, item_code)
  values (v_template_id, 'sale', 1, 'sugar_generic_bag');

  insert into public.template_item_alias (template_id, item_code, language_code, alias_text)
  values (v_template_id, 'sugar_generic_bag', 'so', 'sonkor');
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id uuid;
  v_second_shop_id uuid;
  v_kind_id uuid;
  v_unit_id uuid;
  v_bag_unit_id uuid;
  v_item_id uuid;
  v_catalog_item_id uuid;
  v_sugar_item_id uuid;
  v_second_sugar_item_id uuid;
  v_template_id uuid;
  v_application_id uuid;
  v_replay_application_id uuid;
  v_supplier_type_id uuid;
  v_supplier_party_type_id uuid;
  v_customer_party_type_id uuid;
  v_failed boolean;
begin
  select shop_id, second_shop_id into v_shop_id, v_second_shop_id from test_ids;
  select id into v_kind_id from public.location_kind where code = 'default';
  select id into v_unit_id from public.unit where code = 'piece';
  select id into v_bag_unit_id from public.unit where code = 'bag';
  select id into v_supplier_party_type_id from public.party_type where code = 'supplier';
  select id into v_customer_party_type_id from public.party_type where code = 'customer';
  select id into v_template_id from public.template where code = 'grocery_v1';

  v_application_id := public.apply_template(
    v_second_shop_id,
    v_template_id,
    array['drinks']
  );

  v_replay_application_id := public.apply_template(
    v_second_shop_id,
    v_template_id,
    array['drinks']
  );

  if v_application_id <> v_replay_application_id then
    raise exception 'template application idempotency did not return the original application';
  end if;

  if (select setup_status from public.shop where id = v_second_shop_id) <> 'template_applied' then
    raise exception 'template application did not advance setup status';
  end if;

  if (
    select count(*)
    from public.template_pack_application
    where shop_id = v_second_shop_id
      and template_application_id = v_application_id
  ) <> 2 then
    raise exception 'template application did not trace required plus selected packs';
  end if;

  select id
  into v_second_sugar_item_id
  from public.item
  where shop_id = v_second_shop_id
    and code = 'sugar_generic_bag';

  if v_second_sugar_item_id is null then
    raise exception 'template application did not activate catalog item';
  end if;

  if (
    select current_stock = 0
      and avg_cost = 0
      and last_cost is null
      and sale_price = 9.75
      and reorder_threshold = 3
    from public.item
    where shop_id = v_second_shop_id
      and id = v_second_sugar_item_id
  ) is not true then
    raise exception 'template item did not start with safe operational defaults';
  end if;

  if (
    select count(*)
    from public.item_alias
    where shop_id = v_second_shop_id
      and item_id = v_second_sugar_item_id
      and alias_text in ('white sugar', 'sonkor')
  ) <> 2 then
    raise exception 'template application did not create catalog and template aliases';
  end if;

  if not exists (
    select 1 from public.shop_setting
    where shop_id = v_second_shop_id and key = 'negative_stock_policy' and source = 'template'
  ) then
    raise exception 'template application did not create shop setting';
  end if;

  if not exists (
    select 1 from public.expense_category
    where shop_id = v_second_shop_id and code = 'rent'
  ) then
    raise exception 'template application did not create expense category';
  end if;

  if not exists (
    select 1
    from public.v_shop_suggestions
    where shop_id = v_second_shop_id
      and screen = 'sale'
      and suggestion_type = 'item'
      and item_id = v_second_sugar_item_id
      and source = 'template'
  ) then
    raise exception 'template application did not seed item suggestion';
  end if;

  if not exists (
    select 1
    from public.v_shop_suggestions
    where shop_id = v_second_shop_id
      and screen = 'sale'
      and suggestion_type = 'quantity'
      and item_id = v_second_sugar_item_id
      and quantity = 1
      and source = 'template'
  ) then
    raise exception 'template application did not seed quantity suggestion';
  end if;

  if not exists (
    select 1
    from public.v_shop_suggestions
    where shop_id = v_second_shop_id
      and screen = 'expense'
      and suggestion_type = 'expense_category'
      and source = 'template'
  ) then
    raise exception 'template application did not seed expense suggestion';
  end if;

  if not exists (
    select 1 from public.supplier_type
    where shop_id = v_second_shop_id and code = 'wholesaler'
  ) then
    raise exception 'template application did not create supplier type';
  end if;

  v_failed := false;
  begin
    perform public.apply_template(v_shop_id, v_template_id, array['missing_pack']);
  exception
    when raise_exception then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'template application allowed an unknown pack';
  end if;

  insert into public.location (shop_id, name, kind_id)
  values (v_shop_id, 'Default', v_kind_id);

  insert into public.shop_setting (shop_id, key, value, source)
  values (v_shop_id, 'negative_stock_policy', '"warn"', 'manual');

  insert into public.expense_category (shop_id, code, name)
  values (v_shop_id, 'rent', 'Rent');

  insert into public.help_channel (shop_id, channel, value)
  values (v_shop_id, 'whatsapp', '+252000000000');

  insert into public.supplier_type (shop_id, code, label)
  values (v_shop_id, 'beverage_supplier', 'Beverage Supplier')
  returning id into v_supplier_type_id;

  select id into v_catalog_item_id
  from public.catalog_item
  where code = 'sugar_generic_bag';

  v_sugar_item_id := public.activate_catalog_item(
    v_shop_id,
    v_catalog_item_id,
    null,
    null,
    9.50,
    null
  );

  if (
    select display_name
    from public.v_item_effective
    where shop_id = v_shop_id and id = v_sugar_item_id
  ) <> 'Sugar Bag' then
    raise exception 'catalog-activated item did not inherit display name';
  end if;

  update public.item
  set name_override = 'Shop Sugar'
  where shop_id = v_shop_id and id = v_sugar_item_id;

  if (
    select display_name
    from public.v_item_effective
    where shop_id = v_shop_id and id = v_sugar_item_id
  ) <> 'Shop Sugar' then
    raise exception 'shop item name override did not win over catalog name';
  end if;

  if (
    select count(*)
    from public.item_unit
    where shop_id = v_shop_id and item_id = v_sugar_item_id and source = 'catalog'
  ) <> 1 then
    raise exception 'catalog activation did not copy catalog unit projection';
  end if;

  perform public.apply_template(v_shop_id, v_template_id, null);

  if (
    select count(*)
    from public.item
    where shop_id = v_shop_id and code = 'sugar_generic_bag'
  ) <> 1 then
    raise exception 'template application duplicated existing shop item';
  end if;

  if (
    select name_override
    from public.item
    where shop_id = v_shop_id and id = v_sugar_item_id
  ) <> 'Shop Sugar' then
    raise exception 'template application overwrote shop item override';
  end if;

  insert into public.item (
    shop_id,
    code,
    name,
    base_unit_id,
    default_sale_unit_id,
    default_receive_unit_id,
    sale_price
  )
  values (v_shop_id, 'candy', 'Candy', v_unit_id, v_unit_id, v_bag_unit_id, 1.00)
  returning id into v_item_id;

  insert into public.item_unit (
    shop_id,
    item_id,
    unit_id,
    conversion_to_base,
    is_base_unit,
    allow_sale,
    allow_receive
  )
  values
    (v_shop_id, v_item_id, v_unit_id, 1, true, true, true),
    (v_shop_id, v_item_id, v_bag_unit_id, 100, false, false, true);

  insert into public.item_alias (shop_id, item_id, alias_text, source)
  values (v_shop_id, v_item_id, 'nacnac', 'manual');

  insert into public.party (shop_id, name, type_id, supplier_type_id)
  values (v_shop_id, 'Hodan Beverages', v_supplier_party_type_id, v_supplier_type_id);

  insert into public.party (shop_id, name, type_id)
  values (v_shop_id, 'Asha Customer', v_customer_party_type_id);

  begin
    insert into public.item_unit (
      shop_id,
      item_id,
      unit_id,
      conversion_to_base
    )
    values (v_second_shop_id, v_item_id, v_unit_id, 1);
    raise exception 'cross-shop item_unit composite FK was not enforced';
  exception
    when foreign_key_violation then
      null;
  end;
end;
$$;

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
      and name = 'shop-documents'
      and public = false
      and file_size_limit = 8388608
      and allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']
  ) then
    raise exception 'shop-documents storage bucket was not configured';
  end if;

  v_document_id := gen_random_uuid();
  v_storage_path := v_shop_id::text || '/documents/' || v_document_id::text || '/image.jpg';

  insert into public.document (
    id,
    shop_id,
    type_id,
    storage_bucket,
    storage_path,
    mime_type,
    size_bytes,
    ocr_status_id
  )
  values (
    v_document_id,
    v_shop_id,
    (select id from public.document_type where code = 'sale_receipt'),
    'shop-documents',
    v_storage_path,
    'image/jpeg',
    1024,
    (select id from public.ocr_status where code = 'pending')
  );

  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('shop-documents', v_storage_path, auth.uid(), '{"mimetype":"image/jpeg"}');

  if not exists (
    select 1
    from storage.objects
    where bucket_id = 'shop-documents'
      and name = v_storage_path
  ) then
    raise exception 'shop user could not read their uploaded document image';
  end if;

  v_bad_document_id := gen_random_uuid();
  v_bad_path := v_shop_id::text || '/bad/' || v_bad_document_id::text || '/image.jpg';
  v_failed := false;
  begin
    insert into public.document (
      id,
      shop_id,
      type_id,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      ocr_status_id
    )
    values (
      v_bad_document_id,
      v_shop_id,
      (select id from public.document_type where code = 'sale_receipt'),
      'shop-documents',
      v_bad_path,
      'image/jpeg',
      1024,
      (select id from public.ocr_status where code = 'pending')
    );
  exception
    when check_violation then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'document allowed invalid storage path shape';
  end if;

  v_failed := false;
  begin
    insert into storage.objects (bucket_id, name, owner)
    values (
      'shop-documents',
      v_shop_id::text || '/documents/' || gen_random_uuid()::text || '/image.jpg',
      auth.uid()
    );
  exception
    when insufficient_privilege or check_violation then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'storage policy allowed object without matching document metadata';
  end if;

  v_failed := false;
  begin
    update storage.objects
    set name = v_storage_path || '/evil'
    where bucket_id = 'shop-documents'
      and name = v_storage_path;
  exception
    when insufficient_privilege or check_violation then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'storage policy allowed invalid object rename';
  end if;

  v_failed := false;
  begin
    delete from storage.objects
    where bucket_id = 'shop-documents'
      and name = v_storage_path;
  exception
    when insufficient_privilege then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'storage objects should not be directly deleted by clients';
  end if;

  delete from public.document
  where id = v_document_id;

  insert into document_test_ids (purpose, document_id, storage_path)
  values ('deleted-before-posting', v_document_id, v_storage_path);

  v_receive_document_id := gen_random_uuid();
  v_receive_storage_path := v_shop_id::text || '/documents/' || v_receive_document_id::text || '/image.jpg';

  insert into public.document (
    id,
    shop_id,
    type_id,
    storage_bucket,
    storage_path,
    mime_type,
    size_bytes,
    ocr_status_id
  )
  values (
    v_receive_document_id,
    v_shop_id,
    (select id from public.document_type where code = 'bono'),
    'shop-documents',
    v_receive_storage_path,
    'image/jpeg',
    2048,
    (select id from public.ocr_status where code = 'pending')
  );

  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('shop-documents', v_receive_storage_path, auth.uid(), '{"mimetype":"image/jpeg"}');

  insert into document_test_ids (purpose, document_id, storage_path)
  values ('receive-bono', v_receive_document_id, v_receive_storage_path);
end;
$$;

reset role;
do $$
declare
  v_deleted_path text;
begin
  select storage_path into v_deleted_path
  from document_test_ids
  where purpose = 'deleted-before-posting';

  if exists (
    select 1
    from storage.objects
    where bucket_id = 'shop-documents'
      and name = v_deleted_path
  ) then
    raise exception 'document delete did not clean up the storage object';
  end if;
end;
$$;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_supplier_id uuid;
  v_customer_id uuid;
  v_expense_category_id uuid;
  v_piece_unit_id uuid;
  v_bag_unit_id uuid;
  v_txn_id uuid;
  v_replay_txn_id uuid;
  v_payment_id uuid;
  v_receive_document_id uuid;
  v_failed boolean;
begin
  select shop_id into v_shop_id from test_ids;
  select id into v_item_id from public.item where shop_id = v_shop_id and code = 'candy';
  select id into v_supplier_id from public.party where shop_id = v_shop_id and name = 'Hodan Beverages';
  select id into v_customer_id from public.party where shop_id = v_shop_id and name = 'Asha Customer';
  select id into v_expense_category_id from public.expense_category where shop_id = v_shop_id and code = 'rent';
  select id into v_piece_unit_id from public.unit where code = 'piece';
  select id into v_bag_unit_id from public.unit where code = 'bag';
  select document_id into v_receive_document_id
  from document_test_ids
  where purpose = 'receive-bono';

  update public.shop
  set setup_status = 'template_applied'
  where id = v_shop_id;

  perform public.post_inventory_adjustment(
    v_shop_id,
    'opening',
    jsonb_build_array(jsonb_build_object(
      'item_id', v_item_id,
      'quantity_delta', 5,
      'unit_cost', 0.04
    )),
    null,
    'opening-candy',
    null,
    'Opening stock'
  );

  if (select setup_status from public.shop where id = v_shop_id) <> 'opening_stock_done' then
    raise exception 'opening stock did not advance setup status';
  end if;

  perform public.complete_shop_setup(v_shop_id);

  if (select setup_status from public.shop where id = v_shop_id) <> 'ready' then
    raise exception 'shop setup was not completed';
  end if;

  v_txn_id := public.post_receive(
    v_shop_id,
    v_supplier_id,
    jsonb_build_array(jsonb_build_object(
      'item_id', v_item_id,
      'quantity', 10,
      'unit_id', v_bag_unit_id,
      'line_total', 50
    )),
    20,
    'cash',
    v_receive_document_id,
    'receive-candy-1',
    null,
    'Receive candy'
  );

  v_replay_txn_id := public.post_receive(
    v_shop_id,
    v_supplier_id,
    jsonb_build_array(jsonb_build_object(
      'item_id', v_item_id,
      'quantity', 10,
      'unit_id', v_bag_unit_id,
      'line_total', 50
    )),
    20,
    'cash',
    v_receive_document_id,
    'receive-candy-1',
    null,
    'Receive candy replay'
  );

  if v_txn_id <> v_replay_txn_id then
    raise exception 'receive idempotency did not return the original transaction';
  end if;

  if (select count(*) from public.txn where shop_id = v_shop_id and client_op_id = 'receive-candy-1') <> 1 then
    raise exception 'receive idempotency inserted duplicate transactions';
  end if;

  delete from public.document
  where id = v_receive_document_id;

  if not exists (
    select 1
    from public.document
    where id = v_receive_document_id
  ) then
    raise exception 'referenced receive document was deleted';
  end if;

  if (select current_stock from public.item where shop_id = v_shop_id and id = v_item_id) <> 1005 then
    raise exception 'receive did not update stock in base units';
  end if;

  if (select avg_cost from public.item where shop_id = v_shop_id and id = v_item_id) <> 0.0500 then
    raise exception 'receive weighted average cost was incorrect';
  end if;

  if (select payable from public.party where shop_id = v_shop_id and id = v_supplier_id) <> 30.00 then
    raise exception 'receive did not create supplier payable for unpaid amount';
  end if;

  if (select count(*) from public.payment where shop_id = v_shop_id and direction = 'O' and amount = 20.00) <> 1 then
    raise exception 'receive did not create outbound payment';
  end if;

  v_txn_id := public.post_sale(
    v_shop_id,
    v_customer_id,
    jsonb_build_array(jsonb_build_object(
      'item_id', v_item_id,
      'quantity', 3,
      'unit_id', v_piece_unit_id,
      'unit_price', 1
    )),
    0,
    null,
    null,
    'sale-debt-1',
    null,
    'Debt sale'
  );

  if (select receivable from public.party where shop_id = v_shop_id and id = v_customer_id) <> 3.00 then
    raise exception 'debt sale did not create customer receivable';
  end if;

  if (select cogs_total from public.transaction_line where shop_id = v_shop_id and transaction_id = v_txn_id) <> 0.15 then
    raise exception 'sale did not snapshot expected COGS';
  end if;

  if (select item_name_snapshot from public.transaction_line where shop_id = v_shop_id and transaction_id = v_txn_id) <> 'Candy' then
    raise exception 'sale did not snapshot item name';
  end if;

  update public.item
  set name_override = 'Local Candy'
  where shop_id = v_shop_id and id = v_item_id;

  if (select item_name_snapshot from public.transaction_line where shop_id = v_shop_id and transaction_id = v_txn_id) <> 'Candy' then
    raise exception 'historical sale line snapshot changed after item override';
  end if;

  perform public.post_sale(
    v_shop_id,
    null,
    jsonb_build_array(jsonb_build_object(
      'item_id', v_item_id,
      'quantity', 2,
      'unit_id', v_piece_unit_id,
      'unit_price', 1
    )),
    2,
    'cash',
    null,
    'sale-cash-1',
    null,
    'Anonymous cash sale'
  );

  if (select current_stock from public.item where shop_id = v_shop_id and id = v_item_id) <> 1000 then
    raise exception 'sales did not decrement stock';
  end if;

  if (select count(*) from public.payment where shop_id = v_shop_id and party_id is null and direction = 'I' and amount = 2.00) <> 1 then
    raise exception 'anonymous cash sale did not create payment row';
  end if;

  v_payment_id := public.post_payment(
    v_shop_id,
    v_customer_id,
    'I',
    1,
    'cash',
    'customer-payment-1',
    null,
    null,
    'Customer paid one dollar'
  );

  if v_payment_id is null then
    raise exception 'customer payment did not return an id';
  end if;

  if (select receivable from public.party where shop_id = v_shop_id and id = v_customer_id) <> 2.00 then
    raise exception 'customer payment did not reduce receivable';
  end if;

  v_failed := false;
  begin
    perform public.post_payment(
      v_shop_id,
      v_customer_id,
      'I',
      99,
      'cash',
      'customer-overpay',
      null,
      null,
      'Overpay'
    );
  exception
    when raise_exception then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'customer overpayment was allowed';
  end if;

  perform public.post_expense(
    v_shop_id,
    v_expense_category_id,
    12,
    'cash',
    null,
    'expense-rent-1',
    null,
    'Rent'
  );

  if (select count(*) from public.stock_movement where shop_id = v_shop_id) <> 4 then
    raise exception 'expense should not create stock movements';
  end if;

  begin
    insert into public.txn (
      shop_id,
      type_id,
      status_id,
      occurred_at,
      total_amount,
      paid_amount
    )
    values (
      v_shop_id,
      (select id from public.transaction_type where code = 'sale'),
      (select id from public.transaction_status where code = 'posted'),
      now(),
      1,
      1
    );
    raise exception 'direct transaction insert was allowed';
  exception
    when insufficient_privilege then
      null;
  end;

  v_failed := false;
  begin
    insert into public.shop_suggestion (
      shop_id,
      screen,
      context_key,
      suggestion_type,
      target_key,
      item_id,
      source,
      rank
    )
    values (
      v_shop_id,
      'sale',
      'global',
      'item',
      'blocked-direct-write',
      v_item_id,
      'manual',
      1
    );
  exception
    when insufficient_privilege then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'direct suggestion insert was allowed';
  end if;

  v_failed := false;
  begin
    perform public.post_sale(
      v_shop_id,
      null,
      jsonb_build_array(jsonb_build_object(
        'item_id', v_item_id,
        'quantity', 0,
        'unit_id', v_piece_unit_id,
        'unit_price', 1
      )),
      0,
      null,
      null,
      'sale-zero-qty',
      null,
      'Invalid zero qty'
    );
  exception
    when raise_exception then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'zero quantity sale was allowed';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_piece_unit_id uuid;
  v_failed boolean;
begin
  select shop_id into v_shop_id from test_ids;
  select id into v_item_id from public.item where shop_id = v_shop_id and code = 'candy';
  select id into v_piece_unit_id from public.unit where code = 'piece';

  perform public.post_sale(
    v_shop_id,
    null,
    jsonb_build_array(jsonb_build_object(
      'item_id', v_item_id,
      'quantity', 1,
      'unit_id', v_piece_unit_id,
      'unit_price', 1
    )),
    1,
    'cash',
    null,
    'cashier-sale-1',
    null,
    'Cashier sale'
  );

  v_failed := false;
  begin
    perform public.post_inventory_adjustment(
      v_shop_id,
      'correction',
      jsonb_build_array(jsonb_build_object(
        'item_id', v_item_id,
        'quantity_delta', 1,
        'unit_cost', 0.05
      )),
      null,
      'cashier-adjustment',
      null,
      'Blocked adjustment'
    );
  exception
    when raise_exception then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'cashier inventory adjustment was allowed';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_supplier_id uuid;
  v_customer_id uuid;
begin
  select shop_id into v_shop_id from test_ids;
  select id into v_item_id from public.item where shop_id = v_shop_id and code = 'candy';
  select id into v_supplier_id from public.party where shop_id = v_shop_id and name = 'Hodan Beverages';
  select id into v_customer_id from public.party where shop_id = v_shop_id and name = 'Asha Customer';

  if not exists (
    select 1
    from public.v_item_stock_truth
    where shop_id = v_shop_id
      and item_id = v_item_id
      and cached_stock = 999
      and ledger_stock = 999
      and stock_variance = 0
      and movement_count = 5
  ) then
    raise exception 'item stock truth did not reconcile cached and ledger stock';
  end if;

  if not exists (
    select 1
    from public.v_party_balance_truth
    where shop_id = v_shop_id
      and party_id = v_supplier_id
      and cached_payable = 30
      and ledger_payable = 30
      and payable_variance = 0
  ) then
    raise exception 'supplier payable truth did not reconcile cached and ledger payable';
  end if;

  if not exists (
    select 1
    from public.v_party_balance_truth
    where shop_id = v_shop_id
      and party_id = v_customer_id
      and cached_receivable = 2
      and ledger_receivable = 2
      and receivable_variance = 0
  ) then
    raise exception 'customer receivable truth did not reconcile cached and ledger receivable';
  end if;

  if not exists (
    select 1
    from public.v_sales_report
    where shop_id = v_shop_id
    group by shop_id
    having count(*) = 3
      and sum(revenue) = 6
      and sum(paid_amount) = 3
      and sum(unpaid_amount) = 3
      and sum(cogs_total) = 0.30
      and sum(gross_profit) = 5.70
  ) then
    raise exception 'sales report did not expose expected sale totals and COGS';
  end if;

  if not exists (
    select 1
    from public.v_receive_report
    where shop_id = v_shop_id
      and supplier_id = v_supplier_id
      and total_amount = 50
      and paid_amount = 20
      and unpaid_amount = 30
      and line_count = 1
  ) then
    raise exception 'receive report did not expose expected supplier receive totals';
  end if;

  if not exists (
    select 1
    from public.v_expense_report
    where shop_id = v_shop_id
      and expense_category_code = 'rent'
      and amount = 12
  ) then
    raise exception 'expense report did not expose expected rent expense';
  end if;

  if not exists (
    select 1
    from public.v_daily_profit
    where shop_id = v_shop_id
      and revenue = 6
      and cogs_total = 0.30
      and gross_profit = 5.70
      and expense_total = 12
      and net_profit = -6.30
      and sale_count = 3
      and expense_count = 1
  ) then
    raise exception 'daily profit view did not aggregate expected profit totals';
  end if;

  if not exists (
    select 1
    from public.v_monthly_profit
    where shop_id = v_shop_id
      and revenue = 6
      and cogs_total = 0.30
      and gross_profit = 5.70
      and expense_total = 12
      and net_profit = -6.30
      and sale_count = 3
      and expense_count = 1
  ) then
    raise exception 'monthly profit view did not aggregate expected profit totals';
  end if;

  if not exists (
    select 1
    from public.shop_item_usage
    where shop_id = v_shop_id
      and item_id = v_item_id
      and sale_count = 3
      and receive_count = 1
      and total_sale_base_quantity = 6
      and total_receive_base_quantity = 1000
  ) then
    raise exception 'item usage profile did not track sale and receive activity';
  end if;

  if not exists (
    select 1
    from public.v_shop_suggestions
    where shop_id = v_shop_id
      and screen = 'sale'
      and suggestion_type = 'item'
      and item_id = v_item_id
      and source = 'learned'
      and usage_count = 3
  ) then
    raise exception 'learned sale item suggestion was not active after repeated sales';
  end if;

  if not exists (
    select 1
    from public.shop_item_entry_profile
    where shop_id = v_shop_id
      and item_id = v_item_id
      and context = 'sale'
      and usage_count = 1
  ) then
    raise exception 'sale quantity profile did not track posted sale quantities';
  end if;

  if not exists (
    select 1
    from public.shop_supplier_item_profile
    where shop_id = v_shop_id
      and supplier_id = v_supplier_id
      and item_id = v_item_id
      and receive_count = 1
      and last_unit_cost = 5
  ) then
    raise exception 'supplier item profile did not track receive defaults';
  end if;

  if not exists (
    select 1
    from public.v_shop_suggestions
    where shop_id = v_shop_id
      and screen = 'receive'
      and context_key = 'supplier:' || v_supplier_id::text
      and suggestion_type = 'supplier_item'
      and item_id = v_item_id
      and party_id = v_supplier_id
      and source = 'learned'
  ) then
    raise exception 'learned supplier item suggestion was not active after receive';
  end if;

  if not exists (
    select 1
    from public.v_shop_suggestions
    where shop_id = v_shop_id
      and screen = 'expense'
      and suggestion_type = 'expense_category'
      and expense_category_code = 'rent'
      and source = 'learned'
  ) then
    raise exception 'learned expense category suggestion was not active after expense';
  end if;

  if not exists (
    select 1
    from public.v_shop_suggestions
    where shop_id = v_shop_id
      and screen = 'payment'
      and suggestion_type = 'payment_method'
      and payment_method_code = 'cash'
      and source = 'learned'
  ) then
    raise exception 'learned payment method suggestion was not active after payment';
  end if;

  if not exists (
    select 1
    from public.shop_party_usage
    where shop_id = v_shop_id
      and party_id = v_customer_id
      and sale_count = 1
      and payment_count = 1
  ) then
    raise exception 'party usage profile did not track customer sale and payment activity';
  end if;
end;
$$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

do $$
declare
  v_shop_id uuid;
  v_item_id uuid;
  v_piece_unit_id uuid;
  v_template_id uuid;
  v_failed boolean;
begin
  select shop_id, item_id, piece_unit_id
  into v_shop_id, v_item_id, v_piece_unit_id
  from transaction_test_ids;
  select id into v_template_id from public.template where code = 'grocery_v1';

  if (select count(*) from public.txn) <> 0 then
    raise exception 'unrelated user can see transactions';
  end if;

  if (
    (select count(*) from public.v_sales_report)
    + (select count(*) from public.v_receive_report)
    + (select count(*) from public.v_expense_report)
    + (select count(*) from public.v_daily_profit)
    + (select count(*) from public.v_item_stock_truth)
    + (select count(*) from public.v_party_balance_truth)
    + (select count(*) from public.v_shop_suggestions)
    + (select count(*) from public.shop_item_usage)
    + (select count(*) from public.shop_supplier_item_profile)
    + (select count(*) from public.shop_party_usage)
    + (select count(*) from storage.objects)
  ) <> 0 then
    raise exception 'unrelated user can see report, suggestion, or storage rows';
  end if;

  v_failed := false;
  begin
    perform public.apply_template(v_shop_id, v_template_id, null);
  exception
    when raise_exception then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'unrelated user applied template';
  end if;

  v_failed := false;
  begin
    insert into storage.objects (bucket_id, name, owner)
    values (
      'shop-documents',
      v_shop_id::text || '/documents/' || gen_random_uuid()::text || '/image.jpg',
      auth.uid()
    );
  exception
    when insufficient_privilege or check_violation then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'unrelated user uploaded a shop document image';
  end if;

  v_failed := false;
  begin
    perform public.post_sale(
      v_shop_id,
      null,
      jsonb_build_array(jsonb_build_object(
        'item_id', v_item_id,
        'quantity', 1,
        'unit_id', v_piece_unit_id,
        'unit_price', 1
      )),
      1,
      'cash',
      null,
      'unrelated-sale-1',
      null,
      'Blocked unrelated sale'
    );
  exception
    when raise_exception then
      v_failed := true;
  end;
  if not v_failed then
    raise exception 'unrelated user posted sale';
  end if;
end;
$$;

reset role;
SQL

echo "Backend migration tests passed"
