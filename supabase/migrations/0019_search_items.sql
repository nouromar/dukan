-- ---------------------------------------------------------------------------
-- search_items — consolidated v2 item picker RPC.
-- ---------------------------------------------------------------------------
--
-- Single canonical entry point for Sale / Receive / Products search. Walks
-- the alias chain across shop and global tables, ranks by source priority
-- (exact-locale > prefix-locale > exact-any > prefix-any), and pre-computes
-- the screen-specific default packaging so the caller can render a tile
-- without a second round-trip.
--
-- Consolidates the contracts that were spread across 0021/0022/0024/0025
-- in the pre-v2 schema. Those files are reduced to header-only stubs that
-- explain the consolidation.
--
-- Contract (data-model-v2 §8.1 + locked decision on critique #7):
--   - Returns one row per match keyed on shop_item_id (activated) OR
--     item_id (unactivated global catalog hit, shop_item_id null).
--   - rank_reason exposes WHY each row matched, so the client can show
--     debug chips during pilot and the rank ordering stays inspectable.
--   - default_shop_item_unit_id is the screen-specific default packaging,
--     resolved server-side (is_default_sale / is_default_receive, falling
--     back to the conversion=1 base unit).
--   - For receive with a party_id, default_unit_last_cost prefers
--     supplier_item_unit_cost over the generic shop_item_unit.last_cost.
--   - Recency boost: shop_items that appear in transaction_line of a
--     posted txn in the last 30 days bubble up within their rank tier.
--
-- The display-name helper (shop_item_display_name) lives in 0013.
--
-- Also defines add_shop_item_alias here per the v2 plan note: aliases
-- belong to the search domain.

-- Drop every prior shape of search_items so the rename is clean.
drop function if exists public.search_items(uuid, text, int);
drop function if exists public.search_items(uuid, text, int, text);
drop function if exists public.search_items(uuid, text, int, text, text);
drop function if exists public.search_items(uuid, text, int, text, text, uuid);
drop function if exists public.search_items(uuid, text, text, text, uuid, int);

create or replace function public.search_items(
  p_shop_id   uuid,
  p_query     text  default '',
  p_screen    text  default 'sale',
  p_locale    text  default 'en',
  p_party_id  uuid  default null,
  p_limit     int   default 50
)
returns table (
  shop_item_id                       uuid,
  item_id                            uuid,
  display_name                       text,
  base_unit_code                     text,
  base_unit_label                    text,
  default_shop_item_unit_id          uuid,
  default_unit_code                  text,
  default_unit_label                 text,
  default_unit_conversion_to_base    numeric,
  default_unit_sale_price            numeric,
  default_unit_last_cost             numeric,
  current_stock                      numeric,
  reorder_threshold                  numeric,
  packaging_label                    text,
  is_activated                       boolean,
  rank_reason                        text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_query   text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_query, '')));
  v_screen  text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_screen, 'sale')));
  v_locale  text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
  v_party   uuid := case when v_screen = 'receive' then p_party_id else null end;
  v_limit   int  := greatest(1, coalesce(p_limit, 50));
  v_pattern text;
  v_is_barcode boolean;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to search items for this shop';
  end if;

  if v_screen not in ('sale', 'receive') then
    raise exception 'p_screen must be sale or receive (got %)', v_screen;
  end if;

  if v_locale = '' then
    v_locale := 'en';
  end if;

  v_pattern    := v_query || '%';
  v_is_barcode := v_query <> '' and v_query ~ '^[0-9]{8,}$';

  return query
  with
  -- -------------------------------------------------------------------
  -- Raw match sources. Each row carries (shop_item_id, item_id) — at
  -- least one is non-null. rank_priority is the ordering tier
  -- (smaller = higher priority):
  --   5  barcode_match            (scanner short-circuit)
  --   10 alias_exact_locale       (shop or global)
  --   20 alias_prefix_locale
  --   30 alias_exact_any
  --   40 alias_prefix_any
  -- A barcode hit also carries forced_shop_item_unit_id so the row
  -- locks the picker to the exact packaging that was scanned.
  -- -------------------------------------------------------------------
  matches as (
    -- Shop-side aliases (exact, locale)
    select
      sia.shop_item_id::uuid                        as shop_item_id,
      null::uuid                                    as item_id,
      10                                            as rank_priority,
      'alias_exact_locale'                          as rank_reason,
      sia.weight                                    as weight,
      null::uuid                                    as forced_shop_item_unit_id
    from public.shop_item_alias sia
    join public.shop_item si
      on si.id = sia.shop_item_id and si.shop_id = sia.shop_id
    where v_query <> ''
      and sia.shop_id = p_shop_id
      and sia.is_active
      and si.is_active
      and sia.language_code = v_locale
      and sia.alias_text_norm = v_query

    union all
    -- Shop-side aliases (prefix, locale)
    select
      sia.shop_item_id,
      null::uuid,
      20,
      'alias_prefix_locale',
      sia.weight,
      null::uuid
    from public.shop_item_alias sia
    join public.shop_item si
      on si.id = sia.shop_item_id and si.shop_id = sia.shop_id
    where v_query <> ''
      and sia.shop_id = p_shop_id
      and sia.is_active
      and si.is_active
      and sia.language_code = v_locale
      and sia.alias_text_norm like v_pattern
      and sia.alias_text_norm <> v_query

    union all
    -- Shop-side aliases (exact, any language)
    select
      sia.shop_item_id,
      null::uuid,
      30,
      'alias_exact_any',
      sia.weight,
      null::uuid
    from public.shop_item_alias sia
    join public.shop_item si
      on si.id = sia.shop_item_id and si.shop_id = sia.shop_id
    where v_query <> ''
      and sia.shop_id = p_shop_id
      and sia.is_active
      and si.is_active
      and (sia.language_code is null or sia.language_code <> v_locale)
      and sia.alias_text_norm = v_query

    union all
    -- Shop-side aliases (prefix, any language)
    select
      sia.shop_item_id,
      null::uuid,
      40,
      'alias_prefix_any',
      sia.weight,
      null::uuid
    from public.shop_item_alias sia
    join public.shop_item si
      on si.id = sia.shop_item_id and si.shop_id = sia.shop_id
    where v_query <> ''
      and sia.shop_id = p_shop_id
      and sia.is_active
      and si.is_active
      and (sia.language_code is null or sia.language_code <> v_locale)
      and sia.alias_text_norm like v_pattern
      and sia.alias_text_norm <> v_query

    union all
    -- Global aliases (exact, locale) — activated shop_item OR unactivated
    select
      si.id                                         as shop_item_id,
      ia.item_id                                    as item_id,
      10,
      'alias_exact_locale',
      ia.weight,
      null::uuid
    from public.item_alias ia
    join public.item i
      on i.id = ia.item_id and i.is_active
    left join public.shop_item si
      on si.item_id = ia.item_id
     and si.shop_id = p_shop_id
     and si.is_active
    where v_query <> ''
      and ia.is_active
      and ia.language_code = v_locale
      and ia.alias_text_norm = v_query

    union all
    -- Global aliases (prefix, locale)
    select
      si.id,
      ia.item_id,
      20,
      'alias_prefix_locale',
      ia.weight,
      null::uuid
    from public.item_alias ia
    join public.item i
      on i.id = ia.item_id and i.is_active
    left join public.shop_item si
      on si.item_id = ia.item_id
     and si.shop_id = p_shop_id
     and si.is_active
    where v_query <> ''
      and ia.is_active
      and ia.language_code = v_locale
      and ia.alias_text_norm like v_pattern
      and ia.alias_text_norm <> v_query

    union all
    -- Global aliases (exact, any language)
    select
      si.id,
      ia.item_id,
      30,
      'alias_exact_any',
      ia.weight,
      null::uuid
    from public.item_alias ia
    join public.item i
      on i.id = ia.item_id and i.is_active
    left join public.shop_item si
      on si.item_id = ia.item_id
     and si.shop_id = p_shop_id
     and si.is_active
    where v_query <> ''
      and ia.is_active
      and (ia.language_code is null or ia.language_code <> v_locale)
      and ia.alias_text_norm = v_query

    union all
    -- Global aliases (prefix, any language)
    select
      si.id,
      ia.item_id,
      40,
      'alias_prefix_any',
      ia.weight,
      null::uuid
    from public.item_alias ia
    join public.item i
      on i.id = ia.item_id and i.is_active
    left join public.shop_item si
      on si.item_id = ia.item_id
     and si.shop_id = p_shop_id
     and si.is_active
    where v_query <> ''
      and ia.is_active
      and (ia.language_code is null or ia.language_code <> v_locale)
      and ia.alias_text_norm like v_pattern
      and ia.alias_text_norm <> v_query

    union all
    -- Shop barcode hit. Pre-locks the row to the exact shop_item_unit.
    select
      siu.shop_item_id,
      null::uuid,
      5,
      'barcode_match',
      1000                                          as weight,
      sib.shop_item_unit_id                         as forced_shop_item_unit_id
    from public.shop_item_barcode sib
    join public.shop_item_unit siu
      on siu.id = sib.shop_item_unit_id and siu.shop_id = sib.shop_id
    join public.shop_item si
      on si.id = siu.shop_item_id and si.shop_id = siu.shop_id
    where v_is_barcode
      and sib.shop_id = p_shop_id
      and sib.is_active
      and si.is_active
      and sib.barcode = v_query

    union all
    -- Global barcode hit. shop_item_id may be null (unactivated). The
    -- forced packaging only applies once the shop has activated; until
    -- then the picker hands the cashier the global match and the next
    -- tap triggers ensure_shop_item.
    select
      si.id                                         as shop_item_id,
      i.id                                          as item_id,
      5,
      'barcode_match',
      1000,
      null::uuid
    from public.item_barcode ib
    join public.item_unit iu on iu.id = ib.item_unit_id
    join public.item i       on i.id  = iu.item_id and i.is_active
    left join public.shop_item si
      on si.item_id = i.id
     and si.shop_id = p_shop_id
     and si.is_active
    where v_is_barcode
      and ib.is_active
      and ib.barcode = v_query
  ),
  -- -------------------------------------------------------------------
  -- Empty-query path: list activated shop_items so the picker has rows
  -- to show before the cashier types anything.
  -- -------------------------------------------------------------------
  empty_query_matches as (
    select
      si.id                                         as shop_item_id,
      null::uuid                                    as item_id,
      100                                           as rank_priority,
      'empty_query'                                 as rank_reason,
      0                                             as weight,
      null::uuid                                    as forced_shop_item_unit_id
    from public.shop_item si
    where v_query = ''
      and si.shop_id = p_shop_id
      and si.is_active
  ),
  all_matches as (
    select * from matches
    union all
    select * from empty_query_matches
  ),
  -- Collapse duplicates: keep the best (lowest rank_priority, highest
  -- weight) per (shop_item_id, item_id) key. coalesce so the key
  -- handles unactivated rows (shop_item_id null) too.
  best_matches as (
    select distinct on (coalesce(am.shop_item_id::text, am.item_id::text))
      am.shop_item_id,
      am.item_id,
      am.rank_priority,
      am.rank_reason,
      am.weight,
      am.forced_shop_item_unit_id
    from all_matches am
    where am.shop_item_id is not null or am.item_id is not null
    order by
      coalesce(am.shop_item_id::text, am.item_id::text),
      am.rank_priority asc,
      am.weight desc,
      am.forced_shop_item_unit_id nulls last
  ),
  -- -------------------------------------------------------------------
  -- Resolve the screen-specific default packaging for each match.
  -- Prefer is_default_<screen>, fall back to the conversion=1 base row.
  -- Barcode hits short-circuit to the forced packaging.
  -- -------------------------------------------------------------------
  with_default_unit as (
    select
      bm.shop_item_id,
      bm.item_id,
      bm.rank_priority,
      bm.rank_reason,
      bm.weight,
      bm.forced_shop_item_unit_id,
      coalesce(
        bm.forced_shop_item_unit_id,
        case
          when bm.shop_item_id is null then null
          else (
            select siu.id
            from public.shop_item_unit siu
            where siu.shop_id = p_shop_id
              and siu.shop_item_id = bm.shop_item_id
              and siu.is_active
              and (
                (v_screen = 'sale'    and siu.is_default_sale)
                or
                (v_screen = 'receive' and siu.is_default_receive)
              )
            limit 1
          )
        end,
        case
          when bm.shop_item_id is null then null
          else (
            select siu.id
            from public.shop_item_unit siu
            where siu.shop_id = p_shop_id
              and siu.shop_item_id = bm.shop_item_id
              and siu.is_active
              and siu.conversion_to_base = 1
            limit 1
          )
        end
      ) as default_shop_item_unit_id
    from best_matches bm
  ),
  -- -------------------------------------------------------------------
  -- Recency boost: any posted transaction_line in the last 30 days
  -- bumps the row up within its rank tier. Activated shop_items only.
  -- -------------------------------------------------------------------
  with_recency as (
    select
      wdu.*,
      case
        when wdu.shop_item_id is null then 0
        when exists (
          select 1
          from public.transaction_line tl
          join public.txn t on t.id = tl.transaction_id
          where tl.shop_id = p_shop_id
            and tl.item_id = wdu.shop_item_id
            and t.status_id = public._ref_id('transaction_status', 'posted')
            and t.posted_at >= pg_catalog.now() - interval '30 days'
        ) then 1
        else 0
      end as recency_boost
    from with_default_unit wdu
  ),
  -- -------------------------------------------------------------------
  -- Final projection: pull packaging, prices, stock, labels.
  -- -------------------------------------------------------------------
  enriched as (
    select
      wr.shop_item_id,
      wr.item_id,
      wr.rank_priority,
      wr.rank_reason,
      wr.weight,
      wr.recency_boost,
      wr.default_shop_item_unit_id,
      -- Activated or not?
      (wr.shop_item_id is not null) as is_activated,
      -- shop_item structural snapshot (when activated)
      si.base_unit_code              as si_base_unit_code,
      si.current_stock               as si_current_stock,
      si.reorder_threshold           as si_reorder_threshold,
      -- global item fallback (for unactivated rows or to fill item_id
      -- when we matched on shop alias and the shop_item is activated)
      i_fallback.base_unit_code      as i_base_unit_code,
      -- Default packaging fields (may be null for unactivated rows)
      siu.unit_code                  as siu_unit_code,
      siu.conversion_to_base         as siu_conversion_to_base,
      siu.sale_price                 as siu_sale_price,
      siu.last_cost                  as siu_last_cost,
      -- Per-supplier last cost override (receive + party only)
      case
        when v_screen = 'receive'
         and v_party is not null
         and siu.id is not null
        then (
          select suc.last_unit_cost
          from public.supplier_item_unit_cost suc
          where suc.shop_id = p_shop_id
            and suc.party_id = v_party
            and suc.shop_item_unit_id = siu.id
          limit 1
        )
        else null
      end as supplier_last_cost
    from with_recency wr
    left join public.shop_item si
      on si.id = wr.shop_item_id and si.shop_id = p_shop_id
    -- Resolve a global item when shop_item lacks one (shop-local items
    -- have item_id null; that's fine and we fall back to si.base_unit_code).
    left join public.item i_fallback
      on i_fallback.id = coalesce(wr.item_id, si.item_id)
    left join public.shop_item_unit siu
      on siu.id = wr.default_shop_item_unit_id
     and siu.shop_id = p_shop_id
  )
  select
    e.shop_item_id,
    -- Surface the provenance item_id whenever we can; null = shop-local.
    coalesce(e.item_id, (
      select si2.item_id from public.shop_item si2
      where si2.id = e.shop_item_id and si2.shop_id = p_shop_id
    )) as item_id,
    -- Display name via the alias chain (shop_item_display_name from 0013).
    case
      when e.shop_item_id is not null
        then public.shop_item_display_name(e.shop_item_id, v_locale)
      when e.item_id is not null then coalesce(
        (
          select ia.alias_text
          from public.item_alias ia
          where ia.item_id = e.item_id
            and ia.is_active
            and ia.is_display
            and ia.language_code = v_locale
          limit 1
        ),
        (
          select ia.alias_text
          from public.item_alias ia
          where ia.item_id = e.item_id
            and ia.is_active
            and ia.is_display
          order by ia.language_code nulls last
          limit 1
        ),
        '(unnamed)'
      )
      else '(unnamed)'
    end as display_name,
    -- Base unit code: shop snapshot wins; fall back to global item.
    coalesce(e.si_base_unit_code, e.i_base_unit_code) as base_unit_code,
    -- Base unit label (translated)
    (
      select public.tr(u.default_label, u.label_translations, v_locale)
      from public.unit u
      where u.code = coalesce(e.si_base_unit_code, e.i_base_unit_code)
      limit 1
    ) as base_unit_label,
    e.default_shop_item_unit_id,
    e.siu_unit_code as default_unit_code,
    (
      select public.tr(u.default_label, u.label_translations, v_locale)
      from public.unit u
      where u.code = e.siu_unit_code
      limit 1
    ) as default_unit_label,
    e.siu_conversion_to_base as default_unit_conversion_to_base,
    e.siu_sale_price as default_unit_sale_price,
    coalesce(e.supplier_last_cost, e.siu_last_cost) as default_unit_last_cost,
    e.si_current_stock as current_stock,
    e.si_reorder_threshold as reorder_threshold,
    -- Packaging label:
    --   conversion=1 → just the unit label (e.g. "kg")
    --   otherwise    → "{conversion} {base_unit_label} {unit_label}"
    --                  with trailing zeros trimmed on the conversion.
    case
      when e.siu_unit_code is null then null
      when e.siu_conversion_to_base = 1 then
        (
          select public.tr(u.default_label, u.label_translations, v_locale)
          from public.unit u
          where u.code = e.siu_unit_code
          limit 1
        )
      else
        pg_catalog.rtrim(pg_catalog.rtrim(e.siu_conversion_to_base::text, '0'), '.')
        || ' '
        || coalesce(
          (
            select public.tr(u.default_label, u.label_translations, v_locale)
            from public.unit u
            where u.code = coalesce(e.si_base_unit_code, e.i_base_unit_code)
            limit 1
          ),
          coalesce(e.si_base_unit_code, e.i_base_unit_code, '')
        )
        || ' '
        || coalesce(
          (
            select public.tr(u.default_label, u.label_translations, v_locale)
            from public.unit u
            where u.code = e.siu_unit_code
            limit 1
          ),
          e.siu_unit_code
        )
    end as packaging_label,
    e.is_activated,
    e.rank_reason
  from enriched e
  order by
    e.rank_priority asc,
    e.recency_boost desc,
    e.weight desc,
    e.is_activated desc,
    -- Resolve display name once more for the ORDER BY tiebreaker. The
    -- helper is stable + parallel-safe so this is cheap.
    case
      when e.shop_item_id is not null
        then public.shop_item_display_name(e.shop_item_id, v_locale)
      else ''
    end asc nulls last
  limit v_limit;
end;
$$;

revoke all on function public.search_items(uuid, text, text, text, uuid, int) from public;
grant execute on function public.search_items(uuid, text, text, text, uuid, int) to authenticated;


-- ---------------------------------------------------------------------------
-- add_shop_item_alias — exposed here so search-domain ergonomics stay
-- together. The function body lives in 0011_catalog_activation.sql; this
-- file does not redefine it. Header comment retained per the v2 plan
-- guidance ("aliases belong in the search domain") so future grep'ers
-- land here when looking for "aliases".
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- list_shop_items — Products screen list.
-- ---------------------------------------------------------------------------
--
-- One row per shop_item the shop has activated or created. Display name
-- resolves through the alias chain via shop_item_display_name. Optional
-- filters: category_id (exact) and query (prefix on any active alias
-- in either shop_item_alias or item_alias).
--
-- Ordered by display_name for the Products list. SECURITY DEFINER,
-- gated by auth_can_access_shop; safe for cashiers (read-only).

create or replace function public.list_shop_items(
  p_shop_id     uuid,
  p_category_id uuid default null,
  p_query       text default null,
  p_locale      text default 'en'
)
returns table (
  shop_item_id      uuid,
  item_id           uuid,
  display_name      text,
  category_name     text,
  base_unit_code    text,
  base_unit_label   text,
  current_stock     numeric,
  reorder_threshold numeric,
  unit_count        int,
  is_active         boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale  text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
  v_query   text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_query, '')));
  v_pattern text;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list items for this shop';
  end if;

  if v_locale = '' then
    v_locale := 'en';
  end if;
  v_pattern := v_query || '%';

  return query
  with filtered as (
    select si.id, si.item_id, si.base_unit_code, si.category_id,
           si.current_stock, si.reorder_threshold, si.is_active
    from public.shop_item si
    where si.shop_id = p_shop_id
      and (p_category_id is null or si.category_id = p_category_id)
      and (
        v_query = ''
        or exists (
          select 1 from public.shop_item_alias sia
          where sia.shop_id = p_shop_id
            and sia.shop_item_id = si.id
            and sia.is_active
            and sia.alias_text_norm like v_pattern
        )
        or exists (
          select 1 from public.item_alias ia
          where ia.item_id = si.item_id
            and ia.is_active
            and ia.alias_text_norm like v_pattern
        )
      )
  )
  select
    f.id as shop_item_id,
    f.item_id,
    public.shop_item_display_name(f.id, v_locale) as display_name,
    (
      select public.tr(c.name, c.name_translations, v_locale)
      from public.category c
      where c.id = f.category_id
    ) as category_name,
    f.base_unit_code,
    (
      select public.tr(u.default_label, u.label_translations, v_locale)
      from public.unit u
      where u.code = f.base_unit_code
    ) as base_unit_label,
    f.current_stock,
    f.reorder_threshold,
    (
      select count(*)::int
      from public.shop_item_unit siu
      where siu.shop_id = p_shop_id
        and siu.shop_item_id = f.id
        and siu.is_active
    ) as unit_count,
    f.is_active
  from filtered f
  order by public.shop_item_display_name(f.id, v_locale) asc;
end;
$$;

revoke all on function public.list_shop_items(uuid, uuid, text, text) from public;
grant execute on function public.list_shop_items(uuid, uuid, text, text) to authenticated;


-- ---------------------------------------------------------------------------
-- get_shop_item — Products editor / detail screen.
-- ---------------------------------------------------------------------------
--
-- Single round trip: returns one jsonb object with four sections —
-- header (shop_item summary), units (every shop_item_unit packaging
-- with both default flags raw), aliases (every active alias on the
-- shop_item, including non-display search aliases), and barcodes
-- (every active shop_item_barcode keyed by packaging).
--
-- We pick aggregated-JSON over three separate RPCs to keep this to one
-- network round-trip — the editor needs all four sections together.
-- The Flutter side parses with `getShopItem` and hands typed lists back.

create or replace function public.get_shop_item(
  p_shop_id      uuid,
  p_shop_item_id uuid,
  p_locale       text default 'en'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale  text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
  v_header  jsonb;
  v_units   jsonb;
  v_aliases jsonb;
  v_barcodes jsonb;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to view items for this shop';
  end if;

  if v_locale = '' then
    v_locale := 'en';
  end if;

  -- Header (single-row ShopItemSummary shape).
  select to_jsonb(h) into v_header
  from (
    select
      si.id as shop_item_id,
      si.item_id,
      public.shop_item_display_name(si.id, v_locale) as display_name,
      (
        select public.tr(c.name, c.name_translations, v_locale)
        from public.category c
        where c.id = si.category_id
      ) as category_name,
      si.base_unit_code,
      (
        select public.tr(u.default_label, u.label_translations, v_locale)
        from public.unit u
        where u.code = si.base_unit_code
      ) as base_unit_label,
      si.current_stock,
      si.reorder_threshold,
      (
        select count(*)::int
        from public.shop_item_unit siu
        where siu.shop_id = p_shop_id
          and siu.shop_item_id = si.id
          and siu.is_active
      ) as unit_count,
      si.is_active
    from public.shop_item si
    where si.shop_id = p_shop_id and si.id = p_shop_item_id
  ) h;

  if v_header is null then
    raise exception 'shop_item % not found in shop %', p_shop_item_id, p_shop_id;
  end if;

  -- Units (ShopItemUnitDetail rows). Mirrors list_shop_item_units's
  -- derived `packaging_label`, but surfaces both default flags raw so
  -- the editor can toggle each independently.
  select coalesce(jsonb_agg(to_jsonb(u_row) order by u_row.sort_order, u_row.conversion_to_base, u_row.unit_code), '[]'::jsonb)
  into v_units
  from (
    select
      siu.id as shop_item_unit_id,
      siu.item_unit_id,
      siu.unit_code,
      public.tr(u.default_label, u.label_translations, v_locale) as unit_label,
      case
        when siu.conversion_to_base = 1 then
          public.tr(u.default_label, u.label_translations, v_locale)
        else
          public._format_conversion(siu.conversion_to_base)
          || ' '
          || coalesce(
            (
              select public.tr(bu.default_label, bu.label_translations, v_locale)
              from public.unit bu
              where bu.code = (
                select base_unit_code from public.shop_item
                where id = p_shop_item_id and shop_id = p_shop_id
              )
            ),
            ''
          )
          || ' '
          || public.tr(u.default_label, u.label_translations, v_locale)
      end as packaging_label,
      siu.conversion_to_base,
      siu.sale_price,
      siu.last_cost,
      siu.is_default_sale,
      siu.is_default_receive,
      (siu.conversion_to_base = 1) as is_base_unit,
      siu.is_active,
      siu.sort_order
    from public.shop_item_unit siu
    join public.unit u on u.code = siu.unit_code
    where siu.shop_id = p_shop_id
      and siu.shop_item_id = p_shop_item_id
  ) u_row;

  -- Aliases (every active row on the shop_item, both display + search).
  select coalesce(jsonb_agg(to_jsonb(a_row) order by a_row.is_display desc, a_row.alias_text), '[]'::jsonb)
  into v_aliases
  from (
    select
      sia.alias_text,
      sia.language_code,
      sia.is_display
    from public.shop_item_alias sia
    where sia.shop_id = p_shop_id
      and sia.shop_item_id = p_shop_item_id
      and sia.is_active
  ) a_row;

  -- Barcodes (every active shop_item_barcode for any of this item's
  -- packagings). is_primary is per (shop_item_unit, barcode).
  select coalesce(jsonb_agg(to_jsonb(b_row) order by b_row.is_primary desc, b_row.barcode), '[]'::jsonb)
  into v_barcodes
  from (
    select
      sib.barcode,
      sib.is_primary
    from public.shop_item_barcode sib
    join public.shop_item_unit siu
      on siu.id = sib.shop_item_unit_id
     and siu.shop_id = sib.shop_id
    where sib.shop_id = p_shop_id
      and siu.shop_item_id = p_shop_item_id
      and sib.is_active
  ) b_row;

  return jsonb_build_object(
    'header',   v_header,
    'units',    v_units,
    'aliases',  v_aliases,
    'barcodes', v_barcodes
  );
end;
$$;

revoke all on function public.get_shop_item(uuid, uuid, text) from public;
grant execute on function public.get_shop_item(uuid, uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- suggest_item_packagings — picker source for the Add packaging sheet.
-- ---------------------------------------------------------------------------
--
-- Returns ranked common packagings the platform team has set up
-- against items sharing the same base unit. Same-category matches
-- rank above cross-category fallback so e.g. dry-goods items see
-- other dry-goods packagings first.
--
-- Inputs:
--   p_base_unit_code  — the current item's base unit (we only suggest
--                       packagings whose source items share this base).
--   p_category_id     — nullable; ranks same-category suggestions first.
--   p_locale          — for the unit_label translation.
--   p_limit           — defaults to 8.
--
-- For v1 this runs live each time. Once the catalog grows, we'll
-- precompute via pg_cron into a precomputed_category_packagings table
-- (see docs/background-jobs.md when it lands).

-- Drop the older lighter signature (pre-shop-aware exclusion) so the
-- new one becomes the canonical entry point.
drop function if exists public.suggest_item_packagings(text, uuid, text, int);

create or replace function public.suggest_item_packagings(
  p_shop_id        uuid,
  p_shop_item_id   uuid,
  p_base_unit_code text,
  p_category_id    uuid default null,
  p_locale         text default 'en',
  p_limit          int default 8
)
returns table (
  unit_code           text,
  unit_label          text,
  conversion_to_base  numeric,
  uses                int,
  source              text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_min_primary constant int := 3;
  v_primary_count int;
begin
  -- Exclude packagings the current shop_item already has so the
  -- cashier can't pick a suggestion that would trip the unique
  -- constraint on (shop_id, shop_item_id, unit_code, conversion).
  -- shop_id passes through the auth guard implicitly via the
  -- shop_item_unit lookup; no extra auth check needed (the data is
  -- catalog data).

  return query
  with grouped as (
    select
      iu.unit_code,
      iu.conversion_to_base,
      bool_or(p_category_id is not null and i.category_id = p_category_id)
        as has_category_match,
      count(*)::int as uses
    from public.item_unit iu
    join public.item i on i.id = iu.item_id
    where iu.is_active
      and i.is_active
      and iu.conversion_to_base <> 1
      and i.base_unit_code = p_base_unit_code
    group by iu.unit_code, iu.conversion_to_base
  ),
  already_added as (
    select siu.unit_code, siu.conversion_to_base
    from public.shop_item_unit siu
    where siu.shop_id = p_shop_id
      and siu.shop_item_id = p_shop_item_id
  ),
  filtered as (
    select g.*
    from grouped g
    where not exists (
      select 1 from already_added a
      where a.unit_code = g.unit_code
        and a.conversion_to_base = g.conversion_to_base
    )
  ),
  primary_list as (
    select *
    from filtered
    where p_category_id is null or has_category_match
  )
  -- Decide between primary-only and primary + cross-category fallback
  -- in two passes. First count primary; if < v_min_primary AND
  -- p_category_id is set, fold in cross-category up to p_limit.
  select
    f.unit_code,
    public.tr(u.default_label, u.label_translations, p_locale) as unit_label,
    f.conversion_to_base,
    f.uses,
    case when f.has_category_match then 'category' else 'cross_category' end
      as source
  from (
    select * from primary_list
    union all
    select *
    from filtered
    where p_category_id is not null
      and not has_category_match
      and (select count(*) from primary_list) < v_min_primary
  ) f
  join public.unit u on u.code = f.unit_code
  order by
    case when f.has_category_match then 0 else 1 end,
    f.uses desc,
    f.unit_code asc,
    f.conversion_to_base asc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.suggest_item_packagings(uuid, uuid, text, uuid, text, int) from public;
grant execute on function public.suggest_item_packagings(uuid, uuid, text, uuid, text, int) to authenticated;


-- ---------------------------------------------------------------------------
-- suggest_category_units — picker source for "How is it sold?" in the
-- mid-sale Add new item sheet.
-- ---------------------------------------------------------------------------
--
-- Returns ranked base-unit candidates by counting how many items in the
-- given category use each unit as their base. The Flutter side adds
-- shopkeeper-friendly framing ("Loose (kg)" / "By piece") so this RPC
-- stays pure-data.

create or replace function public.suggest_category_units(
  p_category_id uuid,
  p_locale      text default 'en',
  p_limit       int default 5
)
returns table (
  unit_code  text,
  unit_label text,
  uses       int
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  return query
  select
    i.base_unit_code as unit_code,
    public.tr(u.default_label, u.label_translations, p_locale) as unit_label,
    count(*)::int as uses
  from public.item i
  join public.unit u on u.code = i.base_unit_code
  where i.is_active
    and i.category_id = p_category_id
  group by i.base_unit_code, u.default_label, u.label_translations
  order by count(*) desc, i.base_unit_code asc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.suggest_category_units(uuid, text, int) from public;
grant execute on function public.suggest_category_units(uuid, text, int) to authenticated;


-- ---------------------------------------------------------------------------
-- suggest_new_item_options — single round trip for the Add new item
-- sheet's "How is it sold?" / "How did the supplier deliver?" picker.
-- ---------------------------------------------------------------------------
--
-- Returns a jsonb object with two arrays:
--
--   base_units      — base-unit candidates ranked by usage in the
--                     category. From suggest_category_units.
--   packaged_units  — non-base packagings used by items in the
--                     category, carrying the implied base unit so the
--                     UI can show "25-kg bag" with the kg base inferred.
--
-- Both arrays use the same category-only-with-fallback rule (primary
-- first; cross-category folded in when sparse) as suggest_item_packagings.

create or replace function public.suggest_new_item_options(
  p_category_id uuid,
  p_locale      text default 'en'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_base_units    jsonb;
  v_packaged_units jsonb;
begin
  -- base_units: distinct base_unit_code across active items, ranked by
  -- count. When p_category_id is null we rank across the whole catalog
  -- (the v1 sheet doesn't ship a category picker yet); otherwise we
  -- restrict to in-category items so the picker stays focused.
  select coalesce(jsonb_agg(row), '[]'::jsonb)
  into v_base_units
  from (
    select jsonb_build_object(
      'unit_code', i.base_unit_code,
      'unit_label',
        public.tr(u.default_label, u.label_translations, p_locale),
      'uses', count(*)::int
    ) as row
    from public.item i
    join public.unit u on u.code = i.base_unit_code
    where i.is_active
      and (p_category_id is null or i.category_id = p_category_id)
    group by i.base_unit_code, u.default_label, u.label_translations
    order by count(*) desc, i.base_unit_code asc
    limit 8
  ) sub;

  -- packaged_units: non-base item_unit rows from category items.
  -- Each row carries the implied base unit so the sheet can show
  -- "25-kg bag" and infer base=kg without a second lookup.
  with grouped as (
    select
      iu.unit_code,
      iu.conversion_to_base,
      i.base_unit_code,
      bool_or(p_category_id is not null
              and i.category_id = p_category_id) as has_category_match,
      count(*)::int as uses
    from public.item_unit iu
    join public.item i on i.id = iu.item_id
    where iu.is_active
      and i.is_active
      and iu.conversion_to_base <> 1
      -- Restrict the cross-category fallback to base units that ARE
      -- used in this category — otherwise we'd suggest packagings for
      -- bases that don't apply (e.g., kg-based bags when the category
      -- is all litre-based items). When no category is given, every
      -- packaging is in-scope.
      and (
        p_category_id is null
        or i.base_unit_code in (
          select distinct base_unit_code
          from public.item
          where is_active and category_id = p_category_id
        )
      )
    group by iu.unit_code, iu.conversion_to_base, i.base_unit_code
  ),
  primary_list as (
    select * from grouped where has_category_match
  )
  select coalesce(jsonb_agg(row order by ord_source, ord_uses desc,
                                       ord_unit, ord_conv), '[]'::jsonb)
  into v_packaged_units
  from (
    select
      jsonb_build_object(
        'unit_code', f.unit_code,
        'unit_label',
          public.tr(u.default_label, u.label_translations, p_locale),
        'conversion_to_base', f.conversion_to_base,
        'base_unit_code', f.base_unit_code,
        'base_unit_label',
          public.tr(bu.default_label, bu.label_translations, p_locale),
        'uses', f.uses,
        'source',
          case when f.has_category_match then 'category'
               else 'cross_category' end
      ) as row,
      case when f.has_category_match then 0 else 1 end as ord_source,
      f.uses as ord_uses,
      f.unit_code as ord_unit,
      f.conversion_to_base as ord_conv
    from (
      select * from primary_list
      union all
      -- Cross-category fallback fires when category was given AND the
      -- primary list is short. When no category is given, the primary
      -- list is empty by construction; fold in every packaging.
      select g.*
      from grouped g
      where not g.has_category_match
        and (
          p_category_id is null
          or (select count(*) from primary_list) < 3
        )
    ) f
    join public.unit u on u.code = f.unit_code
    join public.unit bu on bu.code = f.base_unit_code
    limit 12
  ) sub;

  return jsonb_build_object(
    'base_units', v_base_units,
    'packaged_units', v_packaged_units
  );
end;
$$;

revoke all on function public.suggest_new_item_options(uuid, text) from public;
grant execute on function public.suggest_new_item_options(uuid, text) to authenticated;
