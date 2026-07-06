-- 0101_supplier_item_alias.sql
--
-- Bono OCR, slice 1 (schema). The per-supplier learned mapping table that turns
-- "this supplier's text X" into "this shop's item Y + packaging Z", plus the
-- bono-text normalizer that keys it.
--
-- Learning is populated ONLY by confirm_bono_suggestion (0102, SECURITY
-- DEFINER) — a cashier cannot INSERT here directly (no INSERT policy/grant),
-- mirroring how shop_item_alias / supplier_item_unit_cost writes are RPC-only.
--
-- Normalization: the design calls for upper + strip-punct + collapse-ws. Only
-- lower(btrim()) exists today (shop_item_alias.alias_text_norm), so we add a
-- dedicated IMMUTABLE helper and drive both the stored norm column and the
-- lookup in 0102 through it — one source of truth.

create or replace function public._norm_bono_text(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  -- UPPER → split digit↔letter boundaries → punctuation runs to a space →
  -- collapse whitespace → trim. The boundary split absorbs the OCR variance in
  -- pack tokens ("25KG"/"25 KG", "1L"/"1 L", "500G"/"500 G"), so "BSMTI 25KG",
  -- "bsmti-25 kg", and "BSMTI  25KG" all collapse to one key "BSMTI 25 KG".
  -- Keeps letters/digits (Somali is Latin); drops punctuation.
  select pg_catalog.btrim(
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(
          pg_catalog.regexp_replace(
            pg_catalog.upper(coalesce(p_text, '')),
            '([[:digit:]])([[:alpha:]])', '\1 \2', 'g'),
          '([[:alpha:]])([[:digit:]])', '\1 \2', 'g'),
        '[[:punct:]]+', ' ', 'g'),
      '[[:space:]]+', ' ', 'g')
  );
$$;

create table public.supplier_item_alias (
  id                uuid primary key default extensions.gen_random_uuid(),
  shop_id           uuid not null references public.shop(id) on delete cascade,
  supplier_party_id uuid not null,
  raw_text          text not null check (length(btrim(raw_text)) > 0),
  raw_text_norm     text generated always as (public._norm_bono_text(raw_text)) stored,
  shop_item_id      uuid not null,
  shop_item_unit_id uuid not null,
  -- Ranks conflicting mappings: "BSMTI 25" confirmed 4× → rice beats the
  -- 1× couscous mapping (0102 orders by confirm_count desc).
  confirm_count     integer not null default 1 check (confirm_count >= 1),
  last_confirmed_at timestamptz not null default now(),
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  -- One row per (supplier text → candidate packaging). Multiple candidates per
  -- text can coexist (a cashier who maps the same text to two items over time);
  -- suggest_receive_lines_from_bono picks the highest confirm_count. This is a
  -- deliberate refinement of design §6.1 (norm-only unique), which contradicts
  -- §6.3/§7.2's "highest confirm_count wins" + "conflicting mappings" story.
  unique (shop_id, supplier_party_id, raw_text_norm, shop_item_unit_id),
  -- Composite FKs on shop_id for cross-row tenant integrity (not RLS alone).
  foreign key (shop_id, supplier_party_id) references public.party(shop_id, id) on delete cascade,
  foreign key (shop_id, shop_item_id)      references public.shop_item(shop_id, id) on delete cascade,
  foreign key (shop_id, shop_item_unit_id) references public.shop_item_unit(shop_id, id) on delete cascade
);

create index supplier_item_alias_lookup_idx
  on public.supplier_item_alias (shop_id, supplier_party_id, raw_text_norm, confirm_count desc, last_confirmed_at desc);

create trigger set_supplier_item_alias_updated_at
  before update on public.supplier_item_alias
  for each row execute function public.set_updated_at();

alter table public.supplier_item_alias enable row level security;

-- Read for shop members + platform staff. No INSERT/UPDATE policy or grant:
-- the ONLY writer is confirm_bono_suggestion (SECURITY DEFINER) — a direct
-- cashier INSERT is RLS-denied (asserted in the harness).
create policy supplier_item_alias_select
on public.supplier_item_alias
for select
using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff());

grant select on public.supplier_item_alias to authenticated;
