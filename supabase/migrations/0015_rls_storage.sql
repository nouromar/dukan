insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'shop-documents',
  'shop-documents',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  updated_at = now();

alter table public.document
  add constraint document_storage_path_shape
  check (
    storage_path ~* (
      '^'
      || shop_id::text
      || '/documents/'
      || id::text
      || '/image\.(jpg|jpeg|png|webp)$'
    )
  )
  not valid;

create or replace function public.storage_object_shop_id(p_name text)
returns uuid
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_match text[];
begin
  v_match := regexp_match(
    p_name,
    '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/documents/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/image\.(jpg|jpeg|png|webp)$',
    'i'
  );

  if v_match is null then
    return null;
  end if;

  return v_match[1]::uuid;
end;
$$;

create or replace function public.storage_object_document_id(p_name text)
returns uuid
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_match text[];
begin
  v_match := regexp_match(
    p_name,
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/documents/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/image\.(jpg|jpeg|png|webp)$',
    'i'
  );

  if v_match is null then
    return null;
  end if;

  return v_match[1]::uuid;
end;
$$;

create or replace function public.storage_object_matches_document(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select p_bucket_id = 'shop-documents'
    and exists (
      select 1
      from public.document d
      where d.shop_id = public.storage_object_shop_id(p_name)
        and d.id = public.storage_object_document_id(p_name)
        and d.storage_bucket = p_bucket_id
        and d.storage_path = p_name
    );
$$;

create or replace function public.storage_object_can_read(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select p_bucket_id = 'shop-documents'
    and exists (
      select 1
      from public.document d
      where d.shop_id = public.storage_object_shop_id(p_name)
        and d.id = public.storage_object_document_id(p_name)
        and d.storage_bucket = p_bucket_id
        and d.storage_path = p_name
        and (
          public.auth_can_access_shop(d.shop_id)
          or public.auth_is_platform_staff(null)
        )
    );
$$;

create or replace function public.storage_object_can_write(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select p_bucket_id = 'shop-documents'
    and exists (
      select 1
      from public.document d
      where d.shop_id = public.storage_object_shop_id(p_name)
        and d.id = public.storage_object_document_id(p_name)
        and d.storage_bucket = p_bucket_id
        and d.storage_path = p_name
        and public.auth_can_access_shop(d.shop_id)
        and (
          d.uploaded_by = auth.uid()
          or public.auth_has_shop_role(d.shop_id, 'owner')
        )
    );
$$;

create or replace function public.document_is_unattached(
  p_shop_id uuid,
  p_document_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select not exists (
    select 1
    from public.txn t
    where t.shop_id = p_shop_id
      and t.document_id = p_document_id
  )
  and not exists (
    select 1
    from public.payment p
    where p.shop_id = p_shop_id
      and p.document_id = p_document_id
  )
  and not exists (
    select 1
    from public.inventory_adjustment ia
    where ia.shop_id = p_shop_id
      and ia.document_id = p_document_id
  );
$$;

create or replace function public.auth_can_delete_document(
  p_shop_id uuid,
  p_document_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select public.auth_has_shop_role(p_shop_id, 'owner')
    and public.document_is_unattached(p_shop_id, p_document_id);
$$;

create or replace function public.delete_storage_object_for_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from storage.objects
  where bucket_id = old.storage_bucket
    and name = old.storage_path;

  return old;
end;
$$;

drop trigger if exists delete_storage_object_after_document_delete on public.document;
create trigger delete_storage_object_after_document_delete
after delete on public.document
for each row execute function public.delete_storage_object_for_document();

grant usage on schema storage to authenticated;
grant select on storage.buckets to authenticated;
grant select, insert, update on storage.objects to authenticated;
grant delete on public.document to authenticated;

alter table storage.objects enable row level security;

drop policy if exists shop_documents_select on storage.objects;
create policy shop_documents_select
on storage.objects
for select
to authenticated
using (
  public.storage_object_can_read(bucket_id, name)
);

drop policy if exists shop_documents_insert on storage.objects;
create policy shop_documents_insert
on storage.objects
for insert
to authenticated
with check (
  public.storage_object_can_write(bucket_id, name)
);

drop policy if exists shop_documents_update on storage.objects;
create policy shop_documents_update
on storage.objects
for update
to authenticated
using (
  public.storage_object_can_write(bucket_id, name)
)
with check (
  public.storage_object_can_write(bucket_id, name)
);

drop policy if exists document_delete on public.document;
create policy document_delete
on public.document
for delete
using (
  public.auth_can_delete_document(shop_id, id)
);

revoke all on function public.storage_object_matches_document(text, text) from public;
revoke all on function public.storage_object_can_read(text, text) from public;
revoke all on function public.storage_object_can_write(text, text) from public;
revoke all on function public.document_is_unattached(uuid, uuid) from public;
revoke all on function public.auth_can_delete_document(uuid, uuid) from public;
grant execute on function public.storage_object_matches_document(text, text) to authenticated;
grant execute on function public.storage_object_can_read(text, text) to authenticated;
grant execute on function public.storage_object_can_write(text, text) to authenticated;
grant execute on function public.document_is_unattached(uuid, uuid) to authenticated;
grant execute on function public.auth_can_delete_document(uuid, uuid) to authenticated;
