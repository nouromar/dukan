-- 0106_fix_bono_upload_rls.sql
--
-- Fix: every bono image upload was blocked by its own Storage RLS.
--
-- The mobile app uploads the object to the shop-documents bucket FIRST, then
-- calls create_bono_document to insert the document row — deliberately, so OCR
-- only enqueues once the image actually exists. But storage_object_can_write
-- (0015) required a MATCHING document row to already exist at insert time. That
-- is a chicken-and-egg: the row can't exist until after the upload, so the
-- upload is always denied (403) → the app shows "could not attach the bono".
--
-- Authorize the write by shop MEMBERSHIP + path shape instead: whoever can post
-- to the shop encoded in the path may upload {shop}/documents/{id}/image.<ext>.
-- storage_object_shop_id already enforces the exact path shape (returns NULL
-- otherwise), so a malformed path or a non-member shop is still denied — and
-- this matches create_bono_document's own auth_can_post_shop gate on the row.
-- Reads (storage_object_can_read) still require the document row; by read time
-- it exists.

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
    and public.storage_object_shop_id(p_name) is not null
    and public.auth_can_post_shop(public.storage_object_shop_id(p_name));
$$;
