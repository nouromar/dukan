-- 0088_admin_delete_shop.sql
--
-- Platform/system-admin "nuke a shop" RPC: removes a shop and ALL of its data.
-- For wiping test shops now, and a real admin capability later (system admin
-- portal). DESTRUCTIVE and irreversible.
--
-- Why it isn't a plain `delete from public.shop`: every shop-scoped table's
-- shop_id is ON DELETE CASCADE, so the cascade would reap them — EXCEPT a set
-- of intra-shop RESTRICT foreign keys (txn→party, payment→txn, alloc→txn,
-- line→shop_item, shop_item→category, plus the txn/payment self-references)
-- that the cascade races and trips. So we pre-clear the referencing rows in
-- dependency order + null the self-refs, then delete the shop to cascade the
-- rest (party, document, settings, categories, learning, audit, memberships,
-- invites, sync, idempotency, …).
--
-- Auth: platform_admin only, mirroring set_platform_config (0067). A shop owner
-- CANNOT delete their own shop. (No service-role convention exists in this
-- codebase; the pattern is security-definer + in-body auth helper.)
--
-- Out of scope: Storage objects (bono photos) — document rows are removed but
-- the blobs in the shop-documents bucket are left for separate GC. Harmless
-- orphans; noted for a future storage-cleanup pass.

create or replace function public.admin_delete_shop(p_shop_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if not public.auth_is_platform_staff('platform_admin') then
    raise exception 'Only a platform admin can delete a shop';
  end if;

  select name into v_name from public.shop where id = p_shop_id;
  if v_name is null then
    raise exception 'Shop % not found', p_shop_id;
  end if;

  -- Null the self-referential / cross RESTRICT FKs so intra-table delete
  -- order can't trip them.
  update public.payment
     set reverses_payment_id = null,
         refund_of_transaction_id = null
   where shop_id = p_shop_id;
  update public.txn
     set reverses_transaction_id = null
   where shop_id = p_shop_id;
  update public.category
     set parent_id = null
   where shop_id = p_shop_id;

  -- Transactional tables, referencing rows first. transaction_line +
  -- stock_movement also cascade from txn, but we delete them explicitly so
  -- the final shop cascade never races a RESTRICT edge.
  delete from public.payment_allocation        where shop_id = p_shop_id;
  delete from public.stock_movement            where shop_id = p_shop_id;
  delete from public.inventory_adjustment_line where shop_id = p_shop_id;
  delete from public.inventory_adjustment      where shop_id = p_shop_id;
  delete from public.transaction_line          where shop_id = p_shop_id;
  delete from public.payment                   where shop_id = p_shop_id;
  delete from public.txn                       where shop_id = p_shop_id;

  -- shop_item must go before the shop-owned category rows the shop cascade
  -- would otherwise reap first (shop_item.category_id is RESTRICT). Its units,
  -- aliases, barcodes and supplier costs all cascade from shop_item.
  delete from public.shop_item                 where shop_id = p_shop_id;

  -- Everything else is shop_id ON DELETE CASCADE.
  delete from public.shop where id = p_shop_id;

  return v_name;
end;
$$;

revoke all on function public.admin_delete_shop(uuid) from public;
grant execute on function public.admin_delete_shop(uuid) to authenticated;
