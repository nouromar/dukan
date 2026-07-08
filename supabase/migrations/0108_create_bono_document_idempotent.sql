-- 0108_create_bono_document_idempotent.sql
--
-- Make create_bono_document idempotent on the document id. Offline bono capture
-- queues the upload; a retried queued upload (e.g. the storage put succeeded but
-- the RPC response was lost) would otherwise hit a unique-violation on the second
-- create_bono_document and dead-letter. Since the document id is client-minted
-- (globally unique), a conflicting id IS the same document, so `on conflict (id)
-- do nothing` + returning the id makes the call safe to repeat. Pairs with
-- `upsert: true` on the Storage upload.
--
-- Append-only (0034 is live on hosted); same signature, so create-or-replace with
-- no drop.

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
  )
  on conflict (id) do nothing;  -- idempotent: same client-minted id = same document

  return p_document_id;
end;
$$;

revoke all on function public.create_bono_document(
  uuid, uuid, text, text, integer
) from public;
grant execute on function public.create_bono_document(
  uuid, uuid, text, text, integer
) to authenticated;
