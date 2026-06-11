-- ---------------------------------------------------------------------------
-- list_categories — locale-resolved category list for the Add new item +
-- shop item editor dropdowns. Returns root-level categories (no parent)
-- ordered by `sort_order` then localized name; the dropdown doesn't
-- yet render nested hierarchies, so a flat list is what the UI needs.
--
-- Stable, security_definer (read-only). Authenticated callers only.
-- ---------------------------------------------------------------------------

create or replace function public.list_categories(
  p_locale text default 'en'
)
returns table (
  id   uuid,
  code text,
  name text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
begin
  if v_locale = '' then
    v_locale := 'en';
  end if;

  return query
  select
    c.id,
    c.code,
    public.tr(c.name, c.name_translations, v_locale) as name
  from public.category c
  where c.is_active
    and c.parent_id is null
  order by c.sort_order asc, public.tr(c.name, c.name_translations, v_locale)
    asc;
end;
$$;

revoke all on function public.list_categories(text) from public;
grant execute on function public.list_categories(text) to authenticated;
