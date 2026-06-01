-- Unified item search for the Sale / Receive / Products screens.
-- Returns a row per candidate the shop could pick, combining:
--   - activated items (public.item) with their stock + sale price
--   - catalog items not yet activated in this shop, ranked below
-- Matches across name, override, and aliases at both layers, plus
-- the catalog product's bilingual translations. Activated rows always
-- rank above catalog candidates; within each group, alphabetical.

create or replace function public.search_items(
  p_shop_id uuid,
  p_query text default '',
  p_limit int default 50
)
returns table (
  item_id uuid,
  catalog_item_id uuid,
  name text,
  base_unit_code text,
  base_unit_label text,
  sale_price numeric,
  current_stock numeric,
  is_activated boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_query text := coalesce(nullif(pg_catalog.btrim(p_query), ''), '');
  v_pattern text := '%' || v_query || '%';
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to search items for this shop';
  end if;

  return query
  with activated as (
    select
      i.id as item_id,
      i.catalog_item_id,
      coalesce(i.name_override, i.name) as name,
      u.code as base_unit_code,
      u.default_label as base_unit_label,
      i.sale_price,
      i.current_stock,
      true as is_activated
    from public.item i
    join public.unit u on u.id = i.base_unit_id
    where i.shop_id = p_shop_id
      and i.is_active
      and (
        v_query = ''
        or i.name ilike v_pattern
        or coalesce(i.name_override, '') ilike v_pattern
        or exists (
          select 1
          from public.item_alias ia
          where ia.shop_id = p_shop_id
            and ia.item_id = i.id
            and ia.alias_text ilike v_pattern
        )
        -- Activated items keep their catalog aliases as a search source
        -- (we don't copy them per-shop under lazy activation).
        or exists (
          select 1
          from public.catalog_item_alias cia
          where cia.catalog_item_id = i.catalog_item_id
            and cia.alias_text ilike v_pattern
        )
        or exists (
          select 1
          from public.catalog_product_translation cpt
          join public.catalog_item ci on ci.concept_id = cpt.concept_id
          where ci.id = i.catalog_item_id
            and cpt.name ilike v_pattern
        )
      )
  ),
  catalog_candidates as (
    select
      null::uuid as item_id,
      ci.id as catalog_item_id,
      cir.name as name,
      cir.base_unit_code,
      u.default_label as base_unit_label,
      cir.suggested_sale_price as sale_price,
      null::numeric as current_stock,
      false as is_activated
    from public.catalog_item ci
    join public.catalog_item_revision cir on cir.id = ci.current_revision_id
    join public.unit u on u.code = cir.base_unit_code and u.is_active
    where ci.is_active
      and not exists (
        select 1
        from public.item i
        where i.shop_id = p_shop_id
          and i.catalog_item_id = ci.id
      )
      and (
        v_query = ''
        or cir.name ilike v_pattern
        or exists (
          select 1
          from public.catalog_product_translation cpt
          where cpt.concept_id = ci.concept_id
            and cpt.name ilike v_pattern
        )
        or exists (
          select 1
          from public.catalog_item_alias cia
          where cia.catalog_item_id = ci.id
            and cia.alias_text ilike v_pattern
        )
      )
  ),
  all_results as (
    select * from activated
    union all
    select * from catalog_candidates
  )
  select
    all_results.item_id,
    all_results.catalog_item_id,
    all_results.name,
    all_results.base_unit_code,
    all_results.base_unit_label,
    all_results.sale_price,
    all_results.current_stock,
    all_results.is_activated
  from all_results
  order by all_results.is_activated desc, all_results.name asc
  limit p_limit;
end;
$$;

revoke all on function public.search_items(uuid, text, int) from public;
grant execute on function public.search_items(uuid, text, int) to authenticated;
