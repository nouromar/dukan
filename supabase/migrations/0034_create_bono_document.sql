-- ---------------------------------------------------------------------------
-- create_bono_document — insert a `public.document` row of type 'bono'
-- after the client has uploaded the image bytes to Supabase Storage.
-- Returns the document id, which the client passes to post_receive as
-- `p_document_id`.
--
-- Client mints the document UUID up front because the `document` table
-- enforces a path shape of `{shop_id}/documents/{document_id}/image.{ext}`
-- (see `document_storage_path_shape` constraint in 0008). The storage
-- upload happens before the row insert, so the id has to exist before
-- the path can be constructed.
-- ---------------------------------------------------------------------------

drop function if exists public.create_bono_document(uuid, text, text, integer);

create or replace function public.create_bono_document(
  p_shop_id      uuid,
  p_document_id  uuid,
  p_storage_path text,
  p_mime_type    text,
  p_size_bytes   integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type_id    uuid;
  v_status_id  uuid;
begin
  if p_shop_id is null or p_document_id is null
     or p_storage_path is null
     or pg_catalog.length(pg_catalog.btrim(p_storage_path)) = 0 then
    raise exception 'Shop id, document id, and storage path are required';
  end if;
  if p_mime_type not in ('image/jpeg', 'image/png', 'image/webp') then
    raise exception 'Unsupported mime type: %', p_mime_type;
  end if;
  if p_size_bytes is null or p_size_bytes <= 0 or p_size_bytes > 8388608 then
    raise exception 'Invalid size_bytes: %', p_size_bytes;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to attach bonos to this shop';
  end if;

  select id into v_type_id from public.document_type where code = 'bono';
  if v_type_id is null then
    raise exception 'document_type bono not seeded';
  end if;

  select id into v_status_id from public.ocr_status where code = 'pending';
  if v_status_id is null then
    raise exception 'ocr_status pending not seeded';
  end if;

  insert into public.document (
    id, shop_id, type_id, storage_bucket, storage_path,
    mime_type, size_bytes, ocr_status_id
  )
  values (
    p_document_id, p_shop_id, v_type_id, 'shop-documents', p_storage_path,
    p_mime_type, p_size_bytes, v_status_id
  );

  return p_document_id;
end;
$$;

revoke all on function public.create_bono_document(
  uuid, uuid, text, text, integer
) from public;
grant execute on function public.create_bono_document(
  uuid, uuid, text, text, integer
) to authenticated;
