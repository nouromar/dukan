-- list_expenses — reverse-chronological list of past expense txns.
-- Same shape as list_sales/list_receives (paginated by `p_before`)
-- plus expense-specific filter params:
--   * p_date_from / p_date_to — clamp by occurred_at
--   * p_category_id — narrow to one expense_category
--
-- Each row carries the category name (locale-resolved) and notes so
-- the history list reads at a glance ("Electricity · $12 · cash").

create or replace function public.list_expenses(
  p_shop_id      uuid,
  p_before       timestamptz default null,
  p_limit        int         default 50,
  p_date_from    timestamptz default null,
  p_date_to      timestamptz default null,
  p_category_id  uuid        default null,
  p_locale       text        default 'en'
)
returns table (
  txn_id              uuid,
  occurred_at         timestamptz,
  posted_at           timestamptz,
  amount              numeric,
  payment_method_code text,
  category_id         uuid,
  category_name       text,
  notes               text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list expenses for this shop';
  end if;
  if v_locale = '' then
    v_locale := 'en';
  end if;

  return query
  with expenses as (
    select t.id,
           t.occurred_at,
           t.posted_at,
           t.total_amount,
           t.payment_method_id,
           t.notes,
           tl.expense_category_id
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    left join public.transaction_line tl
      on tl.shop_id = t.shop_id and tl.transaction_id = t.id
    where t.shop_id = p_shop_id
      and tt.code = 'expense'
      and t.reverses_transaction_id is null
  )
  select
    e.id as txn_id,
    e.occurred_at,
    e.posted_at,
    e.total_amount as amount,
    pm.code as payment_method_code,
    e.expense_category_id as category_id,
    public.tr(ec.name, ec.name_translations, v_locale) as category_name,
    e.notes
  from expenses e
  left join public.expense_category ec on ec.id = e.expense_category_id
  left join public.payment_method pm on pm.id = e.payment_method_id
  where (p_before     is null or e.occurred_at <  p_before)
    and (p_date_from  is null or e.occurred_at >= p_date_from)
    and (p_date_to    is null or e.occurred_at <  p_date_to)
    and (p_category_id is null or e.expense_category_id = p_category_id)
  order by e.occurred_at desc, e.id desc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_expenses(uuid, timestamptz, int, timestamptz, timestamptz, uuid, text) from public;
grant execute on function public.list_expenses(uuid, timestamptz, int, timestamptz, timestamptz, uuid, text) to authenticated;
