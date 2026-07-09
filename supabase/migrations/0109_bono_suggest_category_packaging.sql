-- 0109_bono_suggest_category_packaging.sql
--
-- Bono OCR, prepopulate v2. Two changes so an UNMATCHED bono line arrives with a
-- proposed category + packaging (today it arrives bare — the cashier types
-- everything). The deterministic item-matching layer is untouched; the AI still
-- never picks a specific shop_item.
--
--   1. ocr_bono_context — now also feeds the model the shop's category list and
--      unit vocabulary, so the model can only echo codes we handed it.
--   2. suggest_receive_lines_from_bono — returns a suggested category + packaging
--      per line: MATCHED lines take the real shop_item category (lookup, no
--      guessing); UNMATCHED lines take the model's proposal, SNAPPED to real
--      category/unit refs (bad/unknown codes fall back to null / base='piece').
--
-- Snapping lives here (SQL) rather than the edge fn so it is harness-testable and
-- is the authoritative gate on what reaches the app.

-- ---------------------------------------------------------------------------
-- ocr_bono_context — add categories + units to the prompt-priming payload
-- ---------------------------------------------------------------------------
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
    ), '[]'::jsonb),
    -- Categories the model may classify a NEW item into: global + this shop's own.
    'categories', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('code', t.code, 'name', t.name)
        order by t.is_custom, t.sort_order, t.name)
      from (
        select c.code,
               public.tr(c.name, c.name_translations, p_locale) as name,
               (c.shop_id is not null) as is_custom,
               c.sort_order
        from public.category c
        where c.is_active
          and c.parent_id is null
          and (c.shop_id is null or c.shop_id = p_shop_id)
      ) t
    ), '[]'::jsonb),
    -- Unit vocabulary the model may propose base + pack units from.
    'units', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('code', u.code, 'label', u.label)
        order by u.code)
      from (
        select un.code,
               public.tr(un.default_label, un.label_translations, p_locale) as label
        from public.unit un
        where un.is_active
      ) u
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.ocr_bono_context(uuid, text) from public;
grant execute on function public.ocr_bono_context(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- suggest_receive_lines_from_bono — add suggested category + packaging columns.
-- Adding OUT columns changes the result type, so drop + recreate.
-- ---------------------------------------------------------------------------
drop function if exists public.suggest_receive_lines_from_bono(uuid, uuid, uuid, text);

create or replace function public.suggest_receive_lines_from_bono(
  p_shop_id           uuid,
  p_document_id       uuid,
  p_supplier_party_id uuid,
  p_locale            text default 'en'
)
returns table (
  line_no                     integer,
  raw_text                    text,
  suggested_shop_item_id      uuid,
  suggested_shop_item_unit_id uuid,
  item_id                     uuid,     -- global catalog item id (null = shop-only)
  display_name                text,
  unit_code                   text,
  conversion_to_base          numeric,
  base_unit_code              text,
  quantity                    numeric,
  unit_price                  numeric,  -- per-packaging cost (pre-fill)
  line_total                  numeric,
  confidence                  text,     -- 'high' | 'med' | 'low'
  reason                      text,     -- 'supplier_alias' | 'shop_alias' | 'no_match'
  -- Suggested category + packaging for the review card. MATCHED lines carry the
  -- real shop_item category; UNMATCHED (new-item) lines carry the AI proposal,
  -- snapped to real refs (else null / base='piece').
  suggested_category_id       uuid,
  suggested_category_code     text,
  suggested_category_name     text,
  suggested_base_unit_code    text,
  suggested_pack_unit_code    text,
  suggested_pack_size         numeric
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_result     jsonb;
  v_line       jsonb;
  v_line_no    integer := 0;
  v_raw        text;
  v_norm       text;
  v_qty        numeric;
  v_ocr_price  numeric;
  v_ocr_total  numeric;
  v_item       uuid;      -- shop_item.id
  v_unit       uuid;      -- shop_item_unit.id
  v_conf       text;
  v_reason     text;
  v_glob_item  uuid;
  v_display    text;
  v_unit_code  text;
  v_conv       numeric;
  v_base_code  text;
  v_price      numeric;
  v_total      numeric;
  v_sug_cat_id    uuid;
  v_sug_cat_code  text;
  v_sug_cat_name  text;
  v_sug_base_code text;
  v_sug_pack_code text;
  v_sug_pack_size numeric;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to read bono suggestions for this shop';
  end if;

  select d.ocr_result into v_result
  from public.document d
  where d.shop_id = p_shop_id and d.id = p_document_id;

  if v_result is null
     or v_result -> 'lines' is null
     or pg_catalog.jsonb_typeof(v_result -> 'lines') <> 'array' then
    return;
  end if;

  for v_line in
    select value from pg_catalog.jsonb_array_elements(v_result -> 'lines')
  loop
    v_line_no   := v_line_no + 1;
    v_raw       := coalesce(v_line ->> 'raw_text', '');
    v_norm      := public._norm_bono_text(v_raw);
    v_qty       := coalesce(nullif(v_line ->> 'quantity', '')::numeric, 1);
    v_ocr_price := nullif(v_line ->> 'unit_price', '')::numeric;
    v_ocr_total := nullif(v_line ->> 'line_total', '')::numeric;
    v_item := null; v_unit := null; v_conf := 'low'; v_reason := 'no_match';

    -- Layer 1: supplier-specific learned alias (exact, normalized). Highest
    -- confirm_count wins; ties broken by most-recent confirmation.
    if v_norm <> '' then
      select sia.shop_item_id, sia.shop_item_unit_id
      into v_item, v_unit
      from public.supplier_item_alias sia
      where sia.shop_id = p_shop_id
        and sia.supplier_party_id = p_supplier_party_id
        and sia.raw_text_norm = v_norm
      order by sia.confirm_count desc, sia.last_confirmed_at desc
      limit 1;
      if v_item is not null then
        v_conf := 'high'; v_reason := 'supplier_alias';
      end if;
    end if;

    -- Layer 2: shop-wide fuzzy alias (trigram) → item only; unit resolved below.
    if v_item is null and pg_catalog.btrim(v_raw) <> '' then
      select fs.shop_item_id into v_item
      from public.find_similar_shop_items(p_shop_id, v_raw, null, p_locale) fs
      limit 1;
      if v_item is not null then
        v_conf := 'med'; v_reason := 'shop_alias';
      end if;
    end if;

    -- Packaging resolution when we have an item but no unit (layer 2), or to
    -- honour the supplier's last-delivered packaging.
    if v_item is not null and v_unit is null then
      -- Prefer the packaging this supplier last delivered for this item.
      select siu.id into v_unit
      from public.supplier_item_unit_cost suc
      join public.shop_item_unit siu
        on siu.shop_id = suc.shop_id and siu.id = suc.shop_item_unit_id
      where suc.shop_id = p_shop_id
        and suc.party_id = p_supplier_party_id
        and siu.shop_item_id = v_item
        and siu.is_active
      order by suc.last_received_at desc nulls last
      limit 1;
      -- Else the receive default, else the lowest-sort active packaging.
      if v_unit is null then
        select siu.id into v_unit
        from public.shop_item_unit siu
        where siu.shop_id = p_shop_id and siu.shop_item_id = v_item and siu.is_active
        order by siu.is_default_receive desc, siu.sort_order asc, siu.conversion_to_base asc
        limit 1;
      end if;
    end if;

    -- Enrich display + cost from the resolved item/unit.
    v_glob_item := null; v_display := null; v_unit_code := null;
    v_conv := null; v_base_code := null; v_price := null; v_total := null;
    if v_item is not null then
      select si.item_id, public.shop_item_display_name(si.id, p_locale), si.base_unit_code
      into v_glob_item, v_display, v_base_code
      from public.shop_item si
      where si.shop_id = p_shop_id and si.id = v_item;

      if v_unit is not null then
        select siu.unit_code, siu.conversion_to_base,
               coalesce(
                 v_ocr_price,
                 (select suc.last_unit_cost from public.supplier_item_unit_cost suc
                   where suc.shop_id = p_shop_id
                     and suc.party_id = p_supplier_party_id
                     and suc.shop_item_unit_id = siu.id),
                 siu.last_cost)
        into v_unit_code, v_conv, v_price
        from public.shop_item_unit siu
        where siu.shop_id = p_shop_id and siu.id = v_unit;
      end if;
    end if;

    -- OCR line_total wins; else derive from the resolved unit price.
    v_total := coalesce(
      v_ocr_total,
      case when v_price is not null then pg_catalog.round(v_price * v_qty, 2) else null end);
    -- If we only have a total, back out a per-unit price for display.
    if v_price is null and v_total is not null and v_qty > 0 then
      v_price := pg_catalog.round(v_total / v_qty, 4);
    end if;

    -- Suggested category + packaging for the review card.
    v_sug_cat_id := null; v_sug_cat_code := null; v_sug_cat_name := null;
    v_sug_base_code := null; v_sug_pack_code := null; v_sug_pack_size := null;

    if v_item is not null then
      -- MATCHED: real category from the shop_item (packaging is in unit_code/base).
      select c.id, c.code, public.tr(c.name, c.name_translations, p_locale)
      into v_sug_cat_id, v_sug_cat_code, v_sug_cat_name
      from public.shop_item si
      left join public.category c on c.id = si.category_id
      where si.shop_id = p_shop_id and si.id = v_item;
    else
      -- UNMATCHED (new item): snap the AI proposal to real refs.
      v_sug_cat_code := nullif(v_line ->> 'suggested_category_code', '');
      if v_sug_cat_code is not null then
        select c.id, c.code, public.tr(c.name, c.name_translations, p_locale)
        into v_sug_cat_id, v_sug_cat_code, v_sug_cat_name
        from public.category c
        where c.is_active
          and c.code = v_sug_cat_code
          and (c.shop_id = p_shop_id or c.shop_id is null)
        order by (c.shop_id is null) asc   -- shop-owned wins over global
        limit 1;
        if not found then
          v_sug_cat_id := null; v_sug_cat_code := null; v_sug_cat_name := null;
        end if;
      end if;

      v_sug_base_code := nullif(v_line ->> 'suggested_base_unit_code', '');
      if v_sug_base_code is null
         or not exists (select 1 from public.unit u where u.code = v_sug_base_code and u.is_active) then
        v_sug_base_code := 'piece';
      end if;

      v_sug_pack_code := nullif(v_line ->> 'suggested_pack_unit_code', '');
      if v_sug_pack_code is not null
         and not exists (select 1 from public.unit u where u.code = v_sug_pack_code and u.is_active) then
        v_sug_pack_code := null;
      end if;

      v_sug_pack_size := nullif(v_line ->> 'suggested_pack_size', '')::numeric;
      if v_sug_pack_size is not null and v_sug_pack_size <= 0 then
        v_sug_pack_size := null;
      end if;
    end if;

    line_no                     := v_line_no;
    raw_text                    := v_raw;
    suggested_shop_item_id      := v_item;
    suggested_shop_item_unit_id := v_unit;
    item_id                     := v_glob_item;
    display_name                := v_display;
    unit_code                   := v_unit_code;
    conversion_to_base          := v_conv;
    base_unit_code              := v_base_code;
    quantity                    := v_qty;
    unit_price                  := v_price;
    line_total                  := v_total;
    confidence                  := v_conf;
    reason                      := v_reason;
    suggested_category_id       := v_sug_cat_id;
    suggested_category_code     := v_sug_cat_code;
    suggested_category_name     := v_sug_cat_name;
    suggested_base_unit_code    := v_sug_base_code;
    suggested_pack_unit_code    := v_sug_pack_code;
    suggested_pack_size         := v_sug_pack_size;
    return next;
  end loop;
  return;
end;
$$;

revoke all on function public.suggest_receive_lines_from_bono(uuid, uuid, uuid, text) from public;
grant execute on function public.suggest_receive_lines_from_bono(uuid, uuid, uuid, text) to authenticated;
