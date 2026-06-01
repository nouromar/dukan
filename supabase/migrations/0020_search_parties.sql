-- Unified party search for the customer / supplier pickers.
-- Returns a row per matching party (customer, supplier, or both kinds)
-- ranked by outstanding balance first so the picker shows people the
-- owner is most likely to be transacting with. Search spans party.name,
-- party_alias.alias_text, and party.phone.
--
-- p_type: 'customer' returns parties whose type is 'customer' or 'both',
--         ranked by receivable desc then name asc.
--         'supplier' returns parties whose type is 'supplier' or 'both',
--         ranked by payable desc then name asc.

create or replace function public.search_parties(
  p_shop_id uuid,
  p_query text default '',
  p_type text default 'customer',
  p_limit int default 50
)
returns table (
  id uuid,
  name text,
  phone text,
  type_code text,
  receivable numeric,
  payable numeric
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_query text := coalesce(nullif(pg_catalog.btrim(p_query), ''), '');
  v_pattern text := '%' || v_query || '%';
  v_normalized_type text := coalesce(nullif(pg_catalog.btrim(p_type), ''), 'customer');
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to search parties for this shop';
  end if;

  if v_normalized_type not in ('customer', 'supplier') then
    raise exception 'p_type must be customer or supplier (got %)', v_normalized_type;
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
      (v_normalized_type = 'customer' and pt.code in ('customer', 'both'))
      or (v_normalized_type = 'supplier' and pt.code in ('supplier', 'both'))
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
  order by
    case v_normalized_type
      when 'customer' then p.receivable
      else p.payable
    end desc,
    p.name asc
  limit p_limit;
end;
$$;

revoke all on function public.search_parties(uuid, text, text, int) from public;
grant execute on function public.search_parties(uuid, text, text, int) to authenticated;
