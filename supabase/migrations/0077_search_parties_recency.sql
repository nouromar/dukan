-- search_parties: add a recency ranking option (p_rank_by).
--
-- Previously ranked by outstanding balance only. The Receive supplier picker
-- and the Debt customer picker want the *recent* people first. This reads
-- shop_party_usage — which the 0014 triggers have been writing on every
-- transaction/payment but which nothing ever read — to order by each party's
-- most recent activity. p_rank_by defaults to 'balance' so existing callers
-- are unchanged (the 4-arg signature resolves to this via the default).

drop function if exists public.search_parties(uuid, text, text, int);

create or replace function public.search_parties(
  p_shop_id uuid,
  p_query   text default '',
  p_type    text default 'customer',
  p_limit   int  default 50,
  p_rank_by text default 'balance'
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
  v_rank_by text := coalesce(nullif(pg_catalog.btrim(p_rank_by), ''), 'balance');
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to search parties for this shop';
  end if;
  if v_normalized_type not in ('customer', 'supplier') then
    raise exception 'p_type must be customer or supplier (got %)', v_normalized_type;
  end if;
  if v_rank_by not in ('balance', 'recency') then
    raise exception 'p_rank_by must be balance or recency (got %)', v_rank_by;
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
  left join public.shop_party_usage spu
    on spu.shop_id = p.shop_id and spu.party_id = p.id
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
    -- Recency tier (only when requested): most-recent activity first, parties
    -- with no activity last. When p_rank_by='balance' this expression is NULL
    -- for every row, so it's a no-op and balance ordering takes over.
    case when v_rank_by = 'recency'
      then greatest(spu.last_sale_at, spu.last_receive_at, spu.last_payment_at)
    end desc nulls last,
    case v_normalized_type
      when 'customer' then p.receivable
      else p.payable
    end desc,
    p.name asc
  limit p_limit;
end;
$$;

revoke all on function public.search_parties(uuid, text, text, int, text) from public;
grant execute on function public.search_parties(uuid, text, text, int, text) to authenticated;
