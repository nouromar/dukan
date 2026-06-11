-- Two RPCs the onboarding + ongoing-edit flows need on the Parties
-- screen:
--
--   1. update_party — rename / phone-update for an existing party.
--      Type (customer/supplier) is intentionally NOT mutable in v1:
--      a party's role anchors its history, and the few times shops
--      need to "promote" a customer to also-supplier the right answer
--      is a separate (admin-portal) flow.
--
--   2. post_opening_party_balance — record that the shopkeeper owed,
--      or was owed by, the party at day-0. Inserts a no-line sale (for
--      receivable) or receive (for payable) txn header, bumps the
--      cached `party.receivable` / `party.payable`, and stamps the
--      notes so reports can flag it ("opening balance"). Idempotent
--      on client_op_id like the other posting RPCs.

-- ---- update_party ----------------------------------------------------------

create or replace function public.update_party(
  p_shop_id  uuid,
  p_party_id uuid,
  p_name     text,
  p_phone    text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name  text;
  v_phone text;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit parties for this shop';
  end if;

  v_name := nullif(pg_catalog.btrim(p_name), '');
  if v_name is null then
    raise exception 'Party name is required';
  end if;
  v_phone := nullif(pg_catalog.btrim(coalesce(p_phone, '')), '');

  update public.party
     set name       = v_name,
         phone      = v_phone,
         updated_at = now()
   where shop_id = p_shop_id
     and id      = p_party_id;
  if not found then
    raise exception 'Party not found in this shop';
  end if;
end;
$$;

revoke all on function public.update_party(uuid, uuid, text, text) from public;
grant execute on function public.update_party(uuid, uuid, text, text) to authenticated;

-- ---- post_opening_party_balance --------------------------------------------

create or replace function public.post_opening_party_balance(
  p_shop_id      uuid,
  p_party_id     uuid,
  p_amount       numeric,
  p_direction    char,         -- 'I' inbound (customer owes us)  → receivable
                                -- 'O' outbound (we owe supplier)  → payable
  p_client_op_id text default null,
  p_notes        text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_id    uuid;
  v_txn_id         uuid;
  v_party_type     text;
  v_type_code      text;
  v_type_id        uuid;
  v_occurred_at    timestamptz := pg_catalog.now();
  v_note           text;
begin
  perform public._require_ready_shop(p_shop_id);

  if p_direction not in ('I', 'O') then
    raise exception 'Direction must be I or O (got %)', p_direction;
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Opening balance amount must be greater than zero';
  end if;

  -- Idempotent on client_op_id.
  if p_client_op_id is not null then
    select id into v_existing_id
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;
    if v_existing_id is not null then
      return v_existing_id;
    end if;
  end if;

  -- Party must exist in this shop and match the side we're posting.
  select pt.code into v_party_type
  from public.party p
  join public.party_type pt on pt.id = p.type_id
  where p.shop_id = p_shop_id and p.id = p_party_id;
  if v_party_type is null then
    raise exception 'Party not found in this shop';
  end if;
  if p_direction = 'I' and v_party_type not in ('customer', 'both') then
    raise exception 'Receivable opening balance requires a customer party';
  end if;
  if p_direction = 'O' and v_party_type not in ('supplier', 'both') then
    raise exception 'Payable opening balance requires a supplier party';
  end if;

  -- Side-specific txn type. Sale = receivable; receive = payable.
  v_type_code := case p_direction when 'I' then 'sale' else 'receive' end;
  v_type_id := public._ref_id('transaction_type', v_type_code);

  v_note := coalesce(
    nullif(pg_catalog.btrim(coalesce(p_notes, '')), ''),
    'Opening balance'
  );

  insert into public.txn (
    shop_id,
    type_id,
    status_id,
    occurred_at,
    posted_at,
    party_id,
    total_amount,
    paid_amount,
    client_op_id,
    notes,
    created_by
  )
  values (
    p_shop_id,
    v_type_id,
    public._ref_id('transaction_status', 'posted'),
    v_occurred_at,
    pg_catalog.now(),
    p_party_id,
    p_amount,
    0,
    p_client_op_id,
    v_note,
    auth.uid()
  )
  returning id into v_txn_id;

  -- Bump the cached projection — same convention as post_sale /
  -- post_receive (denormalized fields written only by posting RPCs).
  if p_direction = 'I' then
    update public.party
       set receivable = receivable + p_amount,
           updated_at = now()
     where shop_id = p_shop_id and id = p_party_id;
  else
    update public.party
       set payable    = payable + p_amount,
           updated_at = now()
     where shop_id = p_shop_id and id = p_party_id;
  end if;

  return v_txn_id;
end;
$$;

revoke all on function public.post_opening_party_balance(uuid, uuid, numeric, char, text, text) from public;
grant execute on function public.post_opening_party_balance(uuid, uuid, numeric, char, text, text) to authenticated;
