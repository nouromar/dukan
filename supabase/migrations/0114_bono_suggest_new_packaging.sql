-- suggest_receive_lines_from_bono: flag a NEW PACKAGING on a matched item.
--
-- Until now a MATCHED line always resolved its unit to one of the item's
-- existing packagings and dropped the AI's detected pack. So when the item
-- matched but the bono was in a packaging the item didn't have yet (Coca-Cola
-- exists as bottle + Carton-12; today's bono is a Carton-24), the review
-- silently bound to an existing pack — wrong stock/cost math unless the
-- cashier noticed and added the size by hand.
--
-- Now: for a matched line we also read + snap the AI's proposed pack and set
-- a new boolean `new_packaging` = the AI gave a real pack (>1 base unit) AND
-- the item has NO active shop_item_unit at that conversion. When true, the
-- pack fields are surfaced so the review can offer a one-tap "Add packaging";
-- the resolved existing unit still rides along as the fallback binding. New
-- items (no match) are unchanged (new_packaging = false; they use Create).
--
-- Adding an OUT column changes the result type → drop + recreate.

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
  item_id                     uuid,
  display_name                text,
  unit_code                   text,
  conversion_to_base          numeric,
  base_unit_code              text,
  quantity                    numeric,
  unit_price                  numeric,
  line_total                  numeric,
  confidence                  text,
  reason                      text,
  suggested_category_id       uuid,
  suggested_category_code     text,
  suggested_category_name     text,
  suggested_base_unit_code    text,
  suggested_pack_unit_code    text,
  suggested_pack_size         numeric,
  -- 0114: true when the line matched an item but the AI's pack is NOT one of
  -- the item's active packagings (a genuinely new size to add).
  new_packaging               boolean
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
  v_item       uuid;
  v_unit       uuid;
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
  v_new_pack      boolean;
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
    v_new_pack := false;

    -- Layer 1: supplier-specific learned alias (exact, normalized).
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

    -- Packaging resolution when we have an item but no unit.
    if v_item is not null and v_unit is null then
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

    v_total := coalesce(
      v_ocr_total,
      case when v_price is not null then pg_catalog.round(v_price * v_qty, 2) else null end);
    if v_price is null and v_total is not null and v_qty > 0 then
      v_price := pg_catalog.round(v_total / v_qty, 4);
    end if;

    v_sug_cat_id := null; v_sug_cat_code := null; v_sug_cat_name := null;
    v_sug_base_code := null; v_sug_pack_code := null; v_sug_pack_size := null;

    if v_item is not null then
      -- MATCHED: real category from the shop_item.
      select c.id, c.code, public.tr(c.name, c.name_translations, p_locale)
      into v_sug_cat_id, v_sug_cat_code, v_sug_cat_name
      from public.shop_item si
      left join public.category c on c.id = si.category_id
      where si.shop_id = p_shop_id and si.id = v_item;

      -- 0114: does the AI's detected pack exist on this item? Snap the pack
      -- code + size, then flag a genuinely new size (pack of >1 base unit at a
      -- conversion the item has no active unit for). When new, surface the
      -- pack fields so the review can offer one-tap "Add packaging".
      v_sug_pack_code := nullif(v_line ->> 'suggested_pack_unit_code', '');
      if v_sug_pack_code is not null
         and not exists (select 1 from public.unit u where u.code = v_sug_pack_code and u.is_active) then
        v_sug_pack_code := null;
      end if;
      v_sug_pack_size := nullif(v_line ->> 'suggested_pack_size', '')::numeric;
      if v_sug_pack_size is not null and v_sug_pack_size <= 1 then
        v_sug_pack_size := null;  -- 1 = base unit (already present); not a pack
      end if;

      if v_sug_pack_code is not null and v_sug_pack_size is not null
         and not exists (
           select 1 from public.shop_item_unit siu
           where siu.shop_id = p_shop_id
             and siu.shop_item_id = v_item
             and siu.is_active
             and siu.conversion_to_base = v_sug_pack_size
         ) then
        v_new_pack      := true;
        v_sug_base_code := v_base_code;  -- add the pack against the item's base
      else
        -- Pack already exists (or none proposed) — no suggestion to surface.
        v_sug_pack_code := null;
        v_sug_pack_size := null;
      end if;
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
        order by (c.shop_id is null) asc
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
    new_packaging               := v_new_pack;
    return next;
  end loop;
  return;
end;
$$;

revoke all on function public.suggest_receive_lines_from_bono(uuid, uuid, uuid, text) from public;
grant execute on function public.suggest_receive_lines_from_bono(uuid, uuid, uuid, text) to authenticated;
