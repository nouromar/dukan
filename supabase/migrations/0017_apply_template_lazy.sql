-- Redefine apply_template for lazy catalog activation (decisions.md Q11,
-- DECIDED 2026-05-31). This supersedes 0012's apply_template entirely.
--
-- New behavior:
--   - Writes shop_setting, expense_category, supplier_type, location, and
--     template_application / template_pack_application traceability.
--   - On FIRST apply only (setup_status = 'not_started'), copies the
--     template's currency/language/timezone onto the shop row so later
--     code reads correct defaults.
--   - Pre-activates only items the template has marked as quick-action
--     favorites (template_quick_action). Everything else stays in the
--     catalog and is activated lazily by post_sale / post_receive /
--     post_inventory_adjustment when the shopkeeper first touches it.
--   - Does NOT loop over every template_item. The candidate list lives
--     in template_item for search ranking but is no longer materialized.
--
-- Off-catalog template items (catalog_item_id IS NULL) are not supported
-- by the lazy pre-activation path; if a future template kind needs them,
-- it will fail loudly here rather than silently materializing.

create or replace function public.apply_template(
  p_shop_id uuid,
  p_template_id uuid,
  p_pack_codes text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_template public.template%rowtype;
  v_application_id uuid;
  v_merge_strategy text;
  v_location_kind_id uuid;
  v_supplier_type record;
  v_supplier_label text;
  v_favorite record;
  v_existing_item_id uuid;
  v_activated_item_id uuid;
  v_timezone_default text;
begin
  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to apply templates for this shop';
  end if;

  perform 1
  from public.shop
  where id = p_shop_id
  for update;

  if not found then
    raise exception 'Shop does not exist';
  end if;

  select *
  into v_template
  from public.template
  where id = p_template_id
    and is_active;

  if v_template.id is null then
    raise exception 'Template is not available';
  end if;

  if p_pack_codes is not null and exists (
    select 1
    from unnest(p_pack_codes) as requested(code)
    where not exists (
      select 1
      from public.template_pack tp
      where tp.template_id = p_template_id
        and tp.code = requested.code
    )
  ) then
    raise exception 'One or more selected template packs do not exist';
  end if;

  select id
  into v_application_id
  from public.template_application
  where shop_id = p_shop_id
    and template_id = p_template_id
    and template_version = v_template.version;

  if v_application_id is not null then
    return v_application_id;
  end if;

  if exists (select 1 from public.template_application where shop_id = p_shop_id) then
    v_merge_strategy := 'merge_update';
  else
    v_merge_strategy := 'first_apply';
  end if;

  insert into public.template_application (
    shop_id, template_id, template_version, applied_by, merge_strategy, status
  )
  values (
    p_shop_id, p_template_id, v_template.version, auth.uid(), v_merge_strategy, 'applying'
  )
  returning id into v_application_id;

  insert into public.template_pack_application (
    shop_id, template_application_id, pack_code, pack_version, status
  )
  select p_shop_id, v_application_id, tp.code, tp.version, 'applied'
  from public.template_pack tp
  where tp.template_id = p_template_id
    and (
      tp.is_required
      or p_pack_codes is null
      or tp.code = any(p_pack_codes)
    )
  on conflict (template_application_id, pack_code) do nothing;

  select id
  into v_location_kind_id
  from public.location_kind
  where code = 'default' and is_active;

  if v_location_kind_id is null then
    raise exception 'Default location kind is not seeded';
  end if;

  insert into public.location (shop_id, name, kind_id, created_by)
  values (p_shop_id, 'Default', v_location_kind_id, auth.uid())
  on conflict (shop_id, name) do nothing;

  insert into public.shop_setting (shop_id, key, value, source, created_by)
  select p_shop_id, ts.key, ts.value, 'template', auth.uid()
  from public.template_setting ts
  where ts.template_id = p_template_id
  on conflict (shop_id, key) do nothing;

  insert into public.expense_category (
    shop_id, code, name, name_translations, created_by
  )
  select p_shop_id, tec.code, tec.name, tec.name_translations, auth.uid()
  from public.template_expense_category tec
  where tec.template_id = p_template_id
  on conflict (shop_id, code) do nothing;

  for v_supplier_type in
    select tst.supplier_type_code, tst.label, tst.sort_order
    from public.template_supplier_type tst
    where tst.template_id = p_template_id
    order by tst.sort_order, tst.supplier_type_code
  loop
    v_supplier_label := coalesce(
      v_supplier_type.label ->> 'en',
      v_supplier_type.label #>> '{}',
      v_supplier_type.supplier_type_code
    );

    insert into public.supplier_type (
      shop_id, code, label, sort_order, created_by
    )
    values (
      p_shop_id, v_supplier_type.supplier_type_code, v_supplier_label,
      v_supplier_type.sort_order, auth.uid()
    )
    on conflict (shop_id, code) do nothing;
  end loop;

  -- Lazy activation: pre-activate ONLY the items the template named as
  -- quick-action favorites, so Home is usable on day one. Skip items
  -- that lack a catalog linkage (lazy path doesn't support custom items),
  -- and skip items that are already activated for this shop.
  for v_favorite in
    select distinct ti.id as template_item_id, ti.catalog_item_id,
                    ti.catalog_revision_id, ti.item_code,
                    ti.suggested_sale_price_override,
                    ti.reorder_threshold_override,
                    ti.name_override
    from public.template_quick_action tqa
    join public.template_item ti
      on ti.template_id = tqa.template_id
     and ti.item_code = tqa.item_code
    where tqa.template_id = p_template_id
      and tqa.item_code is not null
      and ti.catalog_item_id is not null
  loop
    select id
    into v_existing_item_id
    from public.item
    where shop_id = p_shop_id
      and (code = v_favorite.item_code
           or catalog_item_id = v_favorite.catalog_item_id);

    if v_existing_item_id is null then
      v_activated_item_id := public.activate_catalog_item(
        p_shop_id,
        v_favorite.catalog_item_id,
        v_favorite.catalog_revision_id,
        v_favorite.item_code,
        v_favorite.suggested_sale_price_override,
        v_favorite.name_override
      );

      -- activate_catalog_item picks up the catalog revision's defaults
      -- but doesn't know about template-level overrides. Apply them now.
      update public.item
      set source_template_item_id = v_favorite.template_item_id,
          reorder_threshold = coalesce(
            v_favorite.reorder_threshold_override,
            reorder_threshold
          )
      where shop_id = p_shop_id
        and id = v_activated_item_id;
    end if;
  end loop;

  -- First apply: adopt the template's currency / language / timezone as
  -- the shop's defaults. Re-applies don't clobber.
  select value #>> '{}'
  into v_timezone_default
  from public.template_setting
  where template_id = p_template_id
    and key = 'timezone_default';

  update public.shop
  set setup_status = 'template_applied',
      currency_code = v_template.currency_default,
      default_language_code = v_template.locale_default,
      timezone = coalesce(v_timezone_default, timezone)
  where id = p_shop_id
    and setup_status = 'not_started';

  update public.template_application
  set status = 'applied'
  where shop_id = p_shop_id
    and id = v_application_id;

  return v_application_id;
exception
  when unique_violation then
    select id
    into v_application_id
    from public.template_application
    where shop_id = p_shop_id
      and template_id = p_template_id
      and template_version = v_template.version;

    if v_application_id is not null then
      return v_application_id;
    end if;

    raise;
end;
$$;

revoke all on function public.apply_template(uuid, uuid, text[]) from public;
grant execute on function public.apply_template(uuid, uuid, text[]) to authenticated;
