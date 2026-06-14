// Inventory module. Read-only product list backed by the
// list_shop_items RPC — same source the mobile catalog screens use,
// so the two surfaces never drift on display names, category labels,
// or default-sale-price resolution.
//
// Inline edits for reorder_threshold + sale_price are tracked as
// the #278 follow-on (need to agree on the optimistic-update pattern
// + audit-log surfacing first).

import { getTranslations, getLocale } from "next-intl/server";
import { formatMoney, formatCount } from "shared";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  ProductsTable,
  type Product,
} from "@/components/inventory/products-table";

type RpcRow = {
  shop_item_id: string;
  item_id: string | null;
  display_name: string;
  category_name: string | null;
  base_unit_code: string;
  base_unit_label: string;
  current_stock: number | string;
  reorder_threshold: number | string | null;
  unit_count: number;
  is_active: boolean;
  default_sale_price: number | string | null;
  any_price_set: boolean;
};

export default async function InventoryPage() {
  const t = await getTranslations("inventory");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();

  if (!currentShop) {
    return (
      <div className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-xl font-medium">{t("noShop.title")}</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          {t("noShop.description")}
        </p>
      </div>
    );
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("list_shop_items", {
    p_shop_id: currentShop.id,
    p_locale: locale,
  });
  if (error) {
    // Surface to Vercel function logs so production diagnostics aren't
    // a black box. Re-throw so Next renders the standard error page.
    console.error(
      "[inventory] list_shop_items failed:",
      JSON.stringify(error),
    );
    throw error;
  }

  const rows = (data as RpcRow[] | null) ?? [];
  const products: Product[] = rows.map((r) => ({
    shop_item_id: r.shop_item_id,
    display_name: r.display_name,
    category_name: r.category_name,
    base_unit_code: r.base_unit_code,
    base_unit_label: r.base_unit_label,
    current_stock: Number(r.current_stock ?? 0),
    reorder_threshold:
      r.reorder_threshold === null ? null : Number(r.reorder_threshold),
    default_sale_price:
      r.default_sale_price === null ? null : Number(r.default_sale_price),
    is_active: r.is_active,
  }));

  const money = (n: number) =>
    formatMoney(n, currentShop.currency_code, locale);
  const count = (n: number) => formatCount(n, locale);

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex items-baseline justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">
          {currentShop.name}
        </h1>
        <span className="text-sm text-muted-foreground">
          {count(products.length)}
        </span>
      </div>
      <ProductsTable
        rows={products}
        formatMoney={money}
        formatCount={count}
      />
    </div>
  );
}
