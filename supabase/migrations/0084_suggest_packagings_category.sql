-- 0084_suggest_packagings_category.sql
--
-- Make the "common packaging" suggestions (AddPackagingSheet) rank
-- same-category packagings first for EVERY launcher — Product detail,
-- Sale, Receive — without each having to plumb a category id through.
--
-- suggest_item_packagings already receives p_shop_item_id, so it can look
-- up the item's own category itself. We derive an effective category:
-- the caller's p_category_id when given (back-compat / override), else
-- shop_item.category_id. The rest of the ranking is unchanged.
--
-- Signature is unchanged, so CREATE OR REPLACE keeps existing grants.

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
  v_category_id uuid;
begin
  -- Effective category: caller override, else the shop_item's own
  -- category. This is what makes category-first work everywhere without
  -- each caller passing an id. No extra auth check needed — same posture
  -- as before (the data read is catalog data; the lookup is scoped to
  -- p_shop_id).
  v_category_id := p_category_id;
  if v_category_id is null then
    select si.category_id into v_category_id
    from public.shop_item si
    where si.shop_id = p_shop_id
      and si.id = p_shop_item_id;
  end if;

  return query
  with grouped as (
    select
      iu.unit_code,
      iu.conversion_to_base,
      bool_or(v_category_id is not null and i.category_id = v_category_id)
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
    where v_category_id is null or has_category_match
  )
  -- Primary-only, or primary + cross-category fallback when fewer than
  -- v_min_primary same-category matches exist.
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
    where v_category_id is not null
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
