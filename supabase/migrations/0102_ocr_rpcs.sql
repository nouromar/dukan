-- 0102_ocr_rpcs.sql
--
-- Bono OCR, slice 1 (RPCs). The matching + learning layer that turns a stored
-- OCR result (document.ocr_result jsonb) into ranked receive-line suggestions,
-- and records the cashier's confirmations back into the learned alias table.
--
-- Both are SECURITY DEFINER + gated on auth_can_post_shop (owner OR cashier):
--   * suggest_receive_lines_from_bono — READ; binds each OCR line to a real
--     shop_item_unit via supplier alias (high) → shop-wide trigram (med) →
--     no match (low). Never touches the AI (works off the stored jsonb).
--   * confirm_bono_suggestion — the sanctioned WRITE path for the learned
--     alias (a cashier cannot INSERT supplier_item_alias directly under RLS).
--
-- The cashier-picked supplier drives the alias key (p_supplier_party_id), not
-- the OCR-detected supplier — matching design §9 ("alias-learning keyed off the
-- cashier-picked supplier").

-- ---------------------------------------------------------------------------
-- suggest_receive_lines_from_bono
-- ---------------------------------------------------------------------------
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
  reason                      text      -- 'supplier_alias' | 'shop_alias' | 'no_match'
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
    return next;
  end loop;
  return;
end;
$$;

revoke all on function public.suggest_receive_lines_from_bono(uuid, uuid, uuid, text) from public;
grant execute on function public.suggest_receive_lines_from_bono(uuid, uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- confirm_bono_suggestion — records a cashier acceptance into the learning loop
-- ---------------------------------------------------------------------------
create or replace function public.confirm_bono_suggestion(
  p_shop_id           uuid,
  p_document_id       uuid,
  p_supplier_party_id uuid,
  p_raw_text          text,
  p_shop_item_id      uuid,
  p_shop_item_unit_id uuid,
  p_confidence        numeric default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to confirm bono suggestions for this shop';
  end if;

  if p_raw_text is null or pg_catalog.btrim(p_raw_text) = '' then
    raise exception 'raw_text is required to learn a supplier alias';
  end if;

  -- Guard tenant integrity: the document, party, item, and unit must all
  -- belong to this shop (the FKs enforce it on the alias insert too).
  if not exists (
    select 1 from public.document d where d.shop_id = p_shop_id and d.id = p_document_id
  ) then
    raise exception 'Document does not belong to this shop';
  end if;

  -- 1. Audit the cashier's choice for the correction corpus.
  insert into public.ocr_correction (
    shop_id, document_id, raw_text, accepted_entity_table, accepted_entity_id, confidence
  ) values (
    p_shop_id, p_document_id, p_raw_text, 'shop_item', p_shop_item_id, p_confidence
  );

  -- 2. Upsert the learned supplier→item mapping (the sanctioned write path).
  --    Re-confirming the same (supplier text → packaging) increments the count;
  --    a different packaging for the same text is a new count-ranked candidate.
  insert into public.supplier_item_alias (
    shop_id, supplier_party_id, raw_text, shop_item_id, shop_item_unit_id, created_by
  ) values (
    p_shop_id, p_supplier_party_id, p_raw_text, p_shop_item_id, p_shop_item_unit_id, auth.uid()
  )
  on conflict (shop_id, supplier_party_id, raw_text_norm, shop_item_unit_id)
  do update set
    confirm_count     = public.supplier_item_alias.confirm_count + 1,
    last_confirmed_at = pg_catalog.now(),
    shop_item_id      = excluded.shop_item_id,
    updated_at        = pg_catalog.now();
end;
$$;

revoke all on function public.confirm_bono_suggestion(uuid, uuid, uuid, text, uuid, uuid, numeric) from public;
grant execute on function public.confirm_bono_suggestion(uuid, uuid, uuid, text, uuid, uuid, numeric) to authenticated;
