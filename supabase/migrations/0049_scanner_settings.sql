-- 0049_scanner_settings.sql
--
-- Owner-configurable scanner timing knobs.
--
-- Source-of-truth path:
--
--   template_setting (per-template defaults)
--      --> apply_template copies into shop_setting
--   shop_setting (per-shop key/value, source='template' or 'manual')
--      --> trigger projects scanner_* keys into shop.scanner_settings
--   shop.scanner_settings jsonb (typed projection for mobile read)
--
-- Mobile reads shop.scanner_settings as a single field on the shop
-- row -- no extra round-trip on session start. Owner edits via the
-- (future) admin portal write to shop_setting; the trigger keeps the
-- projection in sync. Defaults are baked into the column DEFAULT
-- *and* the projection helper, so an empty shop_setting still gives
-- the cashier the v1 baseline.
--
-- Key shape: shop_setting / template_setting reject dotted keys
-- (check constraint = `[a-z][a-z0-9_]*`), so we use the `scanner_`
-- prefix. The projection strips it: `scanner_rearm_ms` -> `rearm_ms`
-- inside the jsonb.
--
-- Knobs (all integer ms / count):
--
--   rearm_ms                      multi-scan same-code dedupe window
--   hid_max_inter_key_gap_ms      HID burst: max gap between keystrokes
--   hid_max_burst_window_ms       HID burst: max total span
--   hid_min_burst_length          HID burst: minimum chars to count
--
-- Defaults match the constants in lib/scanner/multi_scan_sheet.dart
-- and lib/scanner/hid_listener.dart prior to this migration.

-- 1. Column on shop with sane defaults.

alter table public.shop
  add column scanner_settings jsonb not null default jsonb_build_object(
    'rearm_ms', 800,
    'hid_max_inter_key_gap_ms', 50,
    'hid_max_burst_window_ms', 200,
    'hid_min_burst_length', 4
  );

-- 2. Template seed for grocery. Same values as the column default;
--    they live here too so the source-of-truth chain works for an
--    admin portal that wants to view "what does grocery ship with?"

insert into public.template_setting (template_id, key, value)
select t.id, s.key, s.value
from public.template t
cross join (values
  ('scanner_rearm_ms',                 to_jsonb(800)),
  ('scanner_hid_max_inter_key_gap_ms', to_jsonb(50)),
  ('scanner_hid_max_burst_window_ms',  to_jsonb(200)),
  ('scanner_hid_min_burst_length',     to_jsonb(4))
) as s(key, value)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, key) do nothing;

-- 3. Projection helper. Rebuilds shop.scanner_settings from every
--    scanner_* key in shop_setting. Defaults survive when a key is
--    missing.

create or replace function public._project_scanner_settings(p_shop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb := jsonb_build_object(
    'rearm_ms', 800,
    'hid_max_inter_key_gap_ms', 50,
    'hid_max_burst_window_ms', 200,
    'hid_min_burst_length', 4
  );
  v_row record;
  v_field text;
begin
  for v_row in
    select key, value
    from public.shop_setting
    where shop_id = p_shop_id and key like 'scanner\_%' escape '\'
  loop
    v_field := substring(v_row.key from 'scanner_(.+)$');
    if v_field is not null then
      v_result := v_result || jsonb_build_object(v_field, v_row.value);
    end if;
  end loop;
  update public.shop set scanner_settings = v_result where id = p_shop_id;
end;
$$;

-- 4. Trigger: any scanner_* mutation on shop_setting fires a
--    re-projection for the affected shop.

create or replace function public._trg_project_scanner_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    if new.key like 'scanner\_%' escape '\' then
      perform public._project_scanner_settings(new.shop_id);
    end if;
  end if;
  if tg_op = 'DELETE' or tg_op = 'UPDATE' then
    if old.key like 'scanner\_%' escape '\' then
      perform public._project_scanner_settings(old.shop_id);
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_project_scanner_settings on public.shop_setting;
create trigger trg_project_scanner_settings
after insert or update or delete on public.shop_setting
for each row execute function public._trg_project_scanner_settings();

-- 5. Backfill -- existing shops that already had scanner_* rows in
--    shop_setting get their projection rebuilt. Shops without any
--    scanner_* keys keep the column default.

do $$
declare v_id uuid;
begin
  for v_id in
    select distinct shop_id
    from public.shop_setting
    where key like 'scanner\_%' escape '\'
  loop
    perform public._project_scanner_settings(v_id);
  end loop;
end;
$$;
