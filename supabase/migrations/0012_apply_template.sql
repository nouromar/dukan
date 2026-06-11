-- apply_template — RPC that materializes a global template into a
-- shop's overlay. Defined here in 0012; superseded by the lazy variant
-- in 0017 (which redefines the same RPC name with a smaller body for
-- the live setup flow). We keep 0012 around because it's the eager
-- reference implementation: applies every template_item, not just the
-- favorites — used by tests that want a fully-populated shop catalog.
--
-- Pipeline (per docs/data-model-v2.md §6 + §8.5):
--   1. Insert template_application (idempotent on (shop_id, template_id,
--      template_version)).
--   2. Seed location, shop_setting, expense_category, supplier_type
--      from the template's flat packs.
--   3. For each template_item ordered by sort_order:
--        - If template_item.item_id is set → activate via ensure_shop_item.
--        - Else (template-defined custom item) → create via create_shop_item
--          and add the additional packagings via create_shop_item_unit.
--        - Apply template-level overrides (reorder_threshold, suggested
--          sale price on the default sale packaging).
--   4. Add template aliases via add_shop_item_alias (both display and
--      search variants).
--   5. Record template_pack_application rows.
--   6. Return the template_application.id.
--
-- Catalog has no revisions in v2 (data-model-v2.md §3) — every reference
-- is direct to item.id. shop_item has no name column; display names live
-- in shop_item_alias.

create or replace function public.apply_template(
  p_shop_id uuid,
  p_template_id uuid,
  p_pack_codes text[] default null,
  p_template_version int default null,
  p_merge_strategy text default null,
  p_client_op_id text default null
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
  v_template_item record;
  v_shop_item_id uuid;
  v_packaging record;
  v_alias record;
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
    and is_active
    and (p_template_version is null or version = p_template_version);

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

  -- Idempotent: same (shop, template, version) returns the prior id.
  select id
  into v_application_id
  from public.template_application
  where shop_id = p_shop_id
    and template_id = v_template.id
    and template_version = v_template.version;

  if v_application_id is not null then
    return v_application_id;
  end if;

  if p_merge_strategy is not null then
    if p_merge_strategy not in ('first_apply', 'merge_update') then
      raise exception 'merge_strategy must be first_apply or merge_update';
    end if;
    v_merge_strategy := p_merge_strategy;
  elsif exists (select 1 from public.template_application where shop_id = p_shop_id) then
    v_merge_strategy := 'merge_update';
  else
    v_merge_strategy := 'first_apply';
  end if;

  insert into public.template_application (
    shop_id,
    template_id,
    template_version,
    applied_by,
    merge_strategy,
    status
  )
  values (
    p_shop_id,
    v_template.id,
    v_template.version,
    auth.uid(),
    v_merge_strategy,
    'applying'
  )
  returning id into v_application_id;

  -- ------------------------------------------------------------------
  -- 1. Default location.
  -- ------------------------------------------------------------------

  select id
  into v_location_kind_id
  from public.location_kind
  where code = 'default'
    and is_active;

  if v_location_kind_id is null then
    raise exception 'Default location kind is not seeded';
  end if;

  insert into public.location (shop_id, name, kind_id, created_by)
  values (p_shop_id, 'Default', v_location_kind_id, auth.uid())
  on conflict (shop_id, name) do nothing;

  -- ------------------------------------------------------------------
  -- 2. Shop settings.
  -- ------------------------------------------------------------------

  insert into public.shop_setting (shop_id, key, value, source, created_by)
  select p_shop_id, ts.key, ts.value, 'template', auth.uid()
  from public.template_setting ts
  where ts.template_id = v_template.id
  on conflict (shop_id, key) do nothing;

  -- ------------------------------------------------------------------
  -- 3. Expense categories.
  -- ------------------------------------------------------------------

  insert into public.expense_category (
    shop_id, code, name, name_translations, created_by
  )
  select p_shop_id, tec.code, tec.name, tec.name_translations, auth.uid()
  from public.template_expense_category tec
  where tec.template_id = v_template.id
  on conflict (shop_id, code) do nothing;

  -- ------------------------------------------------------------------
  -- 4. Supplier types.
  -- ------------------------------------------------------------------

  for v_supplier_type in
    select tst.supplier_type_code, tst.label, tst.sort_order
    from public.template_supplier_type tst
    where tst.template_id = v_template.id
    order by tst.sort_order, tst.supplier_type_code
  loop
    v_supplier_label := coalesce(
      v_supplier_type.label ->> 'en',
      v_supplier_type.label #>> '{}',
      v_supplier_type.supplier_type_code
    );

    insert into public.supplier_type (
      shop_id, code, label, label_translations, sort_order, created_by
    )
    values (
      p_shop_id,
      v_supplier_type.supplier_type_code,
      v_supplier_label,
      coalesce(v_supplier_type.label, '{}'::jsonb),
      v_supplier_type.sort_order,
      auth.uid()
    )
    on conflict (shop_id, code) do nothing;
  end loop;

  -- ------------------------------------------------------------------
  -- 5. Items. For each template_item, activate from global catalog
  --    (ensure_shop_item) or create as a shop-local item
  --    (create_shop_item). Then apply overrides, packagings, aliases.
  -- ------------------------------------------------------------------

  for v_template_item in
    select ti.*
    from public.template_item ti
    where ti.template_id = v_template.id
    order by ti.sort_order, ti.item_code
  loop
    if v_template_item.item_id is not null then
      -- Activate from the global catalog. ensure_shop_item is
      -- idempotent + snapshots base_unit / category / packagings /
      -- display aliases for us.
      v_shop_item_id := public.ensure_shop_item(
        p_shop_id,
        v_template_item.item_id
      );

      -- Apply template-level price hint on the default sale packaging.
      -- shop_item_unit.sale_price is owned by the shop; we only set it
      -- if the cashier hasn't already priced this packaging.
      if v_template_item.suggested_sale_price is not null then
        update public.shop_item_unit
        set sale_price = v_template_item.suggested_sale_price
        where shop_id = p_shop_id
          and shop_item_id = v_shop_item_id
          and is_default_sale
          and sale_price is null;
      end if;
    else
      -- Template-defined custom item. create_shop_item makes the
      -- shop_item + the conversion=1 base packaging + a display alias.
      v_shop_item_id := public.create_shop_item(
        p_shop_id,
        v_template_item.custom_name,
        v_template.locale_default,
        v_template_item.base_unit_code_override,
        v_template_item.suggested_sale_price,
        null
      );

      -- Add the additional packagings (skip the conversion=1 row —
      -- create_shop_item already inserted it).
      for v_packaging in
        select tiu.unit_code, tiu.conversion_to_base, tiu.sort_order
        from public.template_item_unit tiu
        where tiu.template_id = v_template.id
          and tiu.item_code = v_template_item.item_code
          and tiu.conversion_to_base <> 1
        order by tiu.sort_order, tiu.unit_code, tiu.conversion_to_base
      loop
        perform public.create_shop_item_unit(
          p_shop_id,
          v_shop_item_id,
          v_packaging.unit_code,
          v_packaging.conversion_to_base,
          null
        );
      end loop;
    end if;

    -- Apply template-level reorder threshold (stored in base units).
    if v_template_item.reorder_threshold is not null then
      update public.shop_item
      set reorder_threshold = v_template_item.reorder_threshold
      where shop_id = p_shop_id
        and id = v_shop_item_id;
    end if;

    -- Template aliases: display rows override the snapshotted display
    -- alias; search rows are added with is_display=false.
    for v_alias in
      select tia.alias_text, tia.language_code, tia.is_display
      from public.template_item_alias tia
      where tia.template_id = v_template.id
        and tia.item_code = v_template_item.item_code
      order by tia.is_display desc, tia.weight desc, tia.alias_text
    loop
      perform public.add_shop_item_alias(
        p_shop_id,
        v_shop_item_id,
        v_alias.alias_text,
        v_alias.language_code,
        v_alias.is_display,
        'manual'
      );
    end loop;
  end loop;

  -- ------------------------------------------------------------------
  -- 6. Pack application traceability.
  -- ------------------------------------------------------------------

  insert into public.template_pack_application (
    shop_id, template_application_id, pack_code, pack_version, status
  )
  select p_shop_id, v_application_id, tp.code, tp.version, 'applied'
  from public.template_pack tp
  where tp.template_id = v_template.id
    and (
      tp.is_required
      or p_pack_codes is null
      or tp.code = any(p_pack_codes)
    )
  on conflict (template_application_id, pack_code) do nothing;

  -- ------------------------------------------------------------------
  -- 7. First-apply: adopt the template's locale / currency / timezone
  --    as the shop's defaults. Re-applies (existing template_application
  --    rows for this shop) don't clobber.
  -- ------------------------------------------------------------------

  select value #>> '{}'
  into v_timezone_default
  from public.template_setting
  where template_id = v_template.id
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
      and template_id = v_template.id
      and template_version = v_template.version;

    if v_application_id is not null then
      return v_application_id;
    end if;

    raise;
end;
$$;

revoke all on function public.apply_template(uuid, uuid, text[], int, text, text) from public;
grant execute on function public.apply_template(uuid, uuid, text[], int, text, text) to authenticated;
