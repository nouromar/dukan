-- list_parties — full directory of parties for the Parties screen.
-- Unlike search_parties (picker; forces a side), this supports a
-- "show me everyone" mode plus type and has-balance filters.
--
-- Filters:
--   * p_query — substring match against name / phone / alias (case-
--               insensitive); empty = no name filter
--   * p_type  — 'customer', 'supplier', or null = both (kind='both'
--               rows always show in either typed scope)
--   * p_has_balance_only — true = only rows with non-zero receivable
--                          (customer side) or payable (supplier side)
--
-- Ordering: outstanding-balance-first so the screen highlights who
-- owes you / who you owe, then alphabetic by name.

create or replace function public.list_parties(
  p_shop_id            uuid,
  p_query              text default '',
  p_type               text default null,
  p_has_balance_only   boolean default false,
  p_limit              int default 200
)
returns table (
  id           uuid,
  name         text,
  phone        text,
  type_code    text,
  receivable   numeric,
  payable      numeric
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_query text := coalesce(nullif(pg_catalog.btrim(p_query), ''), '');
  v_pattern text := '%' || v_query || '%';
  v_type text := nullif(pg_catalog.btrim(coalesce(p_type, '')), '');
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list parties for this shop';
  end if;
  if v_type is not null and v_type not in ('customer', 'supplier') then
    raise exception 'p_type must be customer, supplier, or null (got %)', v_type;
  end if;

  return query
  select
    p.id,
    p.name,
    p.phone,
    pt.code as type_code,
    p.receivable,
    p.payable
  from public.party p
  join public.party_type pt on pt.id = p.type_id
  where p.shop_id = p_shop_id
    and p.is_active
    and (
      v_type is null
      or (v_type = 'customer' and pt.code in ('customer', 'both'))
      or (v_type = 'supplier' and pt.code in ('supplier', 'both'))
    )
    and (
      v_query = ''
      or p.name ilike v_pattern
      or coalesce(p.phone, '') ilike v_pattern
      or exists (
        select 1
        from public.party_alias pa
        where pa.shop_id = p_shop_id
          and pa.party_id = p.id
          and pa.alias_text ilike v_pattern
      )
    )
    and (
      not p_has_balance_only
      or (
        case v_type
          when 'customer' then p.receivable > 0
          when 'supplier' then p.payable > 0
          else (p.receivable > 0 or p.payable > 0)
        end
      )
    )
  order by
    (p.receivable + p.payable) desc,
    p.name asc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_parties(uuid, text, text, boolean, int) from public;
grant execute on function public.list_parties(uuid, text, text, boolean, int) to authenticated;
