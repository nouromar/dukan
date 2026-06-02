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
  v_item record;
  v_item_id uuid;
  v_base_unit_id uuid;
  v_default_sale_unit_id uuid;
  v_default_receive_unit_id uuid;
  v_inserted_units integer;
  v_label text;
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
    shop_id,
    template_id,
    template_version,
    applied_by,
    merge_strategy,
    status
  )
  values (
    p_shop_id,
    p_template_id,
    v_template.version,
    auth.uid(),
    v_merge_strategy,
    'applying'
  )
  returning id into v_application_id;

  insert into public.template_pack_application (
    shop_id,
    template_application_id,
    pack_code,
    pack_version,
    status
  )
  select
    p_shop_id,
    v_application_id,
    tp.code,
    tp.version,
    'applied'
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
  where code = 'default'
    and is_active;

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
    shop_id,
    code,
    name,
    name_translations,
    created_by
  )
  select
    p_shop_id,
    tec.code,
    tec.name,
    tec.name_translations,
    auth.uid()
  from public.template_expense_category tec
  where tec.template_id = p_template_id
  on conflict (shop_id, code) do nothing;

  for v_item in
    select tst.supplier_type_code, tst.label, tst.sort_order
    from public.template_supplier_type tst
    where tst.template_id = p_template_id
    order by tst.sort_order, tst.supplier_type_code
  loop
    v_label := coalesce(v_item.label ->> 'en', v_item.label #>> '{}', v_item.supplier_type_code);

    insert into public.supplier_type (
      shop_id,
      code,
      label,
      sort_order,
      created_by
    )
    values (
      p_shop_id,
      v_item.supplier_type_code,
      v_label,
      v_item.sort_order,
      auth.uid()
    )
    on conflict (shop_id, code) do nothing;
  end loop;

  for v_item in
    select ti.*
    from public.template_item ti
    where ti.template_id = p_template_id
    order by ti.sort_order, ti.item_code
  loop
    select id
    into v_item_id
    from public.item
    where shop_id = p_shop_id
      and code = v_item.item_code;

    if v_item_id is null then
      if v_item.catalog_item_id is not null then
        v_item_id := public.activate_catalog_item(
          p_shop_id,
          v_item.catalog_item_id,
          v_item.catalog_revision_id,
          v_item.item_code,
          v_item.suggested_sale_price_override,
          v_item.name_override
        );

        update public.item
        set source_template_item_id = v_item.id,
            reorder_threshold = coalesce(v_item.reorder_threshold_override, reorder_threshold)
        where shop_id = p_shop_id
          and id = v_item_id;
      else
        select id into v_base_unit_id
        from public.unit
        where code = v_item.base_unit_code_override
          and is_active;

        select id into v_default_sale_unit_id
        from public.unit
        where code = v_item.default_sale_unit_code_override
          and is_active;

        select id into v_default_receive_unit_id
        from public.unit
        where code = v_item.default_receive_unit_code_override
          and is_active;

        if v_base_unit_id is null
          or v_default_sale_unit_id is null
          or v_default_receive_unit_id is null then
          raise exception 'Template item % references inactive or missing units', v_item.item_code;
        end if;

        insert into public.item (
          shop_id,
          code,
          source_template_item_id,
          name,
          name_override,
          base_unit_id,
          default_sale_unit_id,
          default_receive_unit_id,
          sale_price,
          reorder_threshold,
          created_by
        )
        values (
          p_shop_id,
          v_item.item_code,
          v_item.id,
          v_item.custom_name,
          v_item.name_override,
          v_base_unit_id,
          v_default_sale_unit_id,
          v_default_receive_unit_id,
          v_item.suggested_sale_price_override,
          v_item.reorder_threshold_override,
          auth.uid()
        )
        returning id into v_item_id;

        insert into public.item_unit (
          shop_id,
          item_id,
          unit_id,
          source,
          conversion_to_base,
          is_base_unit,
          sort_order,
          created_by
        )
        select
          p_shop_id,
          v_item_id,
          u.id,
          'template',
          tiu.conversion_to_base,
          tiu.unit_code = v_item.base_unit_code_override,
          tiu.sort_order,
          auth.uid()
        from public.template_item_unit tiu
        join public.unit u on u.code = tiu.unit_code and u.is_active
        where tiu.template_id = p_template_id
          and tiu.item_code = v_item.item_code
        on conflict (shop_id, item_id, unit_id) do nothing;

        get diagnostics v_inserted_units = row_count;

        if v_inserted_units = 0 then
          raise exception 'Template item % has no active units', v_item.item_code;
        end if;

        if not exists (
          select 1
          from public.item_unit
          where shop_id = p_shop_id
            and item_id = v_item_id
            and is_base_unit
        ) then
          raise exception 'Template item % must include one base unit', v_item.item_code;
        end if;
      end if;
    end if;

    insert into public.item_unit (
      shop_id,
      item_id,
      unit_id,
      source,
      conversion_to_base,
      is_base_unit,
      sort_order,
      created_by
    )
    select
      p_shop_id,
      v_item_id,
      u.id,
      'template',
      tiu.conversion_to_base,
      false,
      tiu.sort_order,
      auth.uid()
    from public.template_item_unit tiu
    join public.unit u on u.code = tiu.unit_code and u.is_active
    where tiu.template_id = p_template_id
      and tiu.item_code = v_item.item_code
      and tiu.unit_code <> coalesce(v_item.base_unit_code_override, '')
    on conflict (shop_id, item_id, unit_id) do nothing;

    insert into public.item_alias (
      shop_id,
      item_id,
      alias_text,
      language_code,
      source,
      created_by
    )
    select
      p_shop_id,
      v_item_id,
      cia.alias_text,
      cia.language_code,
      'template',
      auth.uid()
    from public.catalog_item_alias cia
    where cia.catalog_item_id = v_item.catalog_item_id
    on conflict (shop_id, alias_text, item_id) do nothing;

    insert into public.item_alias (
      shop_id,
      item_id,
      alias_text,
      language_code,
      source,
      created_by
    )
    select
      p_shop_id,
      v_item_id,
      tia.alias_text,
      tia.language_code,
      'template',
      auth.uid()
    from public.template_item_alias tia
    where tia.template_id = p_template_id
      and tia.item_code = v_item.item_code
    on conflict (shop_id, alias_text, item_id) do nothing;
  end loop;

  update public.shop
  set setup_status = 'template_applied'
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
