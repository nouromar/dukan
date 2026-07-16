-- 0117_regional_currencies.sql
--
-- Add East African currencies for regional expansion: Tanzania, Uganda, South
-- Sudan. (Ethiopian Birr `ETB` and Kenyan Shilling `KES` are already seeded in
-- 0081.) Decimals follow how the currency is used in practice — the shilling
-- cents are obsolete, so TZS/UGX carry 0 like SOS/SLSH; the South Sudanese
-- Pound uses piasters, so 2.
--
-- Idempotent (ON CONFLICT DO UPDATE), matching 0081, so re-runs / fresh
-- environments converge. A NEW migration (not an edit to 0081) so `db push`
-- actually deploys it to already-migrated backends.

insert into public.currency (code, name, symbol, decimals, is_active) values
  ('TZS', 'Tanzanian Shilling',   'TSh', 0, true),
  ('UGX', 'Ugandan Shilling',     'USh', 0, true),
  ('SSP', 'South Sudanese Pound', 'SSP', 2, true)
on conflict (code) do update set
  name      = excluded.name,
  symbol    = excluded.symbol,
  decimals  = excluded.decimals,
  is_active = excluded.is_active;
