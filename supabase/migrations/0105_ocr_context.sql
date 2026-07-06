-- 0105_ocr_context.sql
--
-- Bono OCR, slice 3 (backend). ocr_bono_context — the prompt-priming payload
-- the ocr-bono edge function feeds Claude: shop name + currency, the shop's
-- recent items (spelling reference, NOT a match target), and recent suppliers
-- (one may appear in the bono header). One SECURITY DEFINER call so the edge fn
-- never touches base tables directly, and the priming is harness-testable.

create or replace function public.ocr_bono_context(p_shop_id uuid, p_locale text default 'so')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'shop_name',     (select s.name from public.shop s where s.id = p_shop_id),
    'currency_code', (select s.currency_code from public.shop s where s.id = p_shop_id),
    'top_items', coalesce((
      select pg_catalog.jsonb_agg(t.name order by t.updated_at desc)
      from (
        select public.shop_item_display_name(si.id, p_locale) as name, si.updated_at
        from public.shop_item si
        where si.shop_id = p_shop_id and si.is_active
        order by si.updated_at desc
        limit 30
      ) t
    ), '[]'::jsonb),
    'top_suppliers', coalesce((
      select pg_catalog.jsonb_agg(v.name order by v.updated_at desc)
      from (
        select pa.name, pa.updated_at
        from public.party pa
        join public.party_type ty on ty.id = pa.type_id
        where pa.shop_id = p_shop_id and pa.is_active and ty.code = 'supplier'
        order by pa.updated_at desc
        limit 20
      ) v
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.ocr_bono_context(uuid, text) from public;
grant execute on function public.ocr_bono_context(uuid, text) to service_role;
