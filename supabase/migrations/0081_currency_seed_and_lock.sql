-- Currency: readable names, a regional seed set (adds Somali Shilling SOS /
-- Sh.So, distinct from Somaliland SLSH), and a lock so a shop can't change its
-- currency once it has posted a transaction.
--
-- Why the lock: the currency is the UNIT of every stored number (totals, COGS,
-- party balances). Changing it after transactions exist would silently corrupt
-- history and reports, and posted transactions are immutable — there is no
-- self-serve conversion in v1. Currency is therefore freely changeable only
-- during setup (zero posted transactions).

-- 1. Readable name for the setup picker (SLSH "Somaliland" vs SOS "Somali").
alter table public.currency add column if not exists name text;

-- 2. Seed. USD/SLSH unchanged (now named); SOS + a regional set added. All
-- active so they're selectable at setup; System Admin can deactivate any.
insert into public.currency (code, name, symbol, decimals, is_active) values
  ('USD',  'US Dollar',           '$',     2, true),
  ('SLSH', 'Somaliland Shilling', 'SLSH',  0, true),
  ('SOS',  'Somali Shilling',     'Sh.So', 0, true),
  ('KES',  'Kenyan Shilling',     'KSh',   2, true),
  ('ETB',  'Ethiopian Birr',      'Br',    2, true),
  ('DJF',  'Djiboutian Franc',    'Fdj',   0, true),
  ('AED',  'UAE Dirham',          'AED',   2, true),
  ('SAR',  'Saudi Riyal',         'SAR',   2, true),
  ('EUR',  'Euro',                '€',     2, true),
  ('GBP',  'British Pound',       '£',     2, true)
on conflict (code) do update set
  name      = excluded.name,
  symbol    = excluded.symbol,
  decimals  = excluded.decimals,
  is_active = excluded.is_active;

-- 3. Lock the currency after the first posted transaction.
create or replace function public.update_shop_settings(
  p_shop_id  uuid,
  p_settings jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before      jsonb;
  v_name        text;
  v_currency    text;
  v_lang        text;
  v_timezone    text;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can edit shop settings';
  end if;

  if p_settings is null
     or pg_catalog.jsonb_typeof(p_settings) <> 'object' then
    raise exception 'p_settings must be a JSON object';
  end if;

  select pg_catalog.jsonb_build_object(
    'name',                  s.name,
    'currency_code',         s.currency_code,
    'default_language_code', s.default_language_code,
    'timezone',              s.timezone
  )
  into v_before
  from public.shop s
  where s.id = p_shop_id;

  if v_before is null then
    raise exception 'Shop not found';
  end if;

  v_name     := nullif(pg_catalog.btrim(p_settings->>'name'), '');
  v_currency := nullif(p_settings->>'currency_code', '');
  v_lang     := nullif(p_settings->>'default_language_code', '');
  v_timezone := nullif(pg_catalog.btrim(p_settings->>'timezone'), '');

  if v_name is null
     and v_currency is null
     and v_lang is null
     and v_timezone is null then
    return;
  end if;

  -- Currency lock: reject a real currency change once any transaction is posted.
  if v_currency is not null
     and v_currency is distinct from (v_before->>'currency_code')
     and exists (
       select 1
       from public.txn t
       join public.transaction_status ts on ts.id = t.status_id
       where t.shop_id = p_shop_id and ts.code = 'posted'
     ) then
    raise exception
      'Currency is locked once the shop has recorded a transaction. '
      'Contact support to change it.';
  end if;

  update public.shop
  set name                  = coalesce(v_name,     name),
      currency_code         = coalesce(v_currency, currency_code),
      default_language_code = coalesce(v_lang,     default_language_code),
      timezone              = coalesce(v_timezone, timezone),
      updated_at            = pg_catalog.now()
  where id = p_shop_id;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'setup.shop.edit',
    p_entity_type  => 'shop',
    p_entity_id    => p_shop_id,
    p_before       => v_before,
    p_after        => pg_catalog.jsonb_build_object(
      'name',                  coalesce(v_name,     v_before->>'name'),
      'currency_code',         coalesce(v_currency, v_before->>'currency_code'),
      'default_language_code', coalesce(v_lang,     v_before->>'default_language_code'),
      'timezone',              coalesce(v_timezone, v_before->>'timezone')
    )
  );
end;
$$;
