-- Extend search_items with an optional p_screen parameter so the Sale
-- and Receive screens get usage-ranked favorites instead of alphabetical.
--
-- When p_screen = 'sale' or 'receive', activated items rank by their
-- usage count from shop_item_usage (sale_count or receive_count, joined
-- with LEFT JOIN so items with no recorded usage sort to the end).
-- Catalog candidates stay alphabetical at the bottom — they have no
-- usage history.
--
-- When p_screen is null, behavior is unchanged from 0019: activated
-- first then alphabetical.
--
-- Drops the original (uuid, text, int) signature so there's only one
-- canonical function name.

drop function if exists public.search_items(uuid, text, int);

create or replace function public.search_items(
  p_shop_id uuid,
  p_query text default '',
  p_limit int default 50,
  p_screen text default null
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
  v_screen text := coalesce(nullif(pg_catalog.btrim(p_screen), ''), '');
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to search items for this shop';
  end if;

  if v_screen <> '' and v_screen not in ('sale', 'receive') then
    raise exception 'p_screen must be sale or receive (got %)', v_screen;
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
      true as is_activated,
      -- Usage-based ranking signal for the active screen. Items the
      -- shop has touched on this screen sort first; ties broken by name.
      case v_screen
        when 'sale'    then coalesce(siu.sale_count, 0)
        when 'receive' then coalesce(siu.receive_count, 0)
        else 0
      end as usage_rank
    from public.item i
    join public.unit u on u.id = i.base_unit_id
    left join public.shop_item_usage siu
      on siu.shop_id = i.shop_id and siu.item_id = i.id
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
      false as is_activated,
      0 as usage_rank
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
  order by
    all_results.is_activated desc,
    all_results.usage_rank desc,
    all_results.name asc
  limit p_limit;
end;
$$;

revoke all on function public.search_items(uuid, text, int, text) from public;
grant execute on function public.search_items(uuid, text, int, text) to authenticated;
