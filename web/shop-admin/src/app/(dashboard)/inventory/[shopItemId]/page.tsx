// Product detail. Single get_shop_item RPC returns header + packaging
// units + aliases + barcodes for the chosen shop_item.
//
// Read-only for now. Add/remove aliases, change default pack, edit
// price come later — all need an audited mutation path.

import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations, getLocale } from "next-intl/server";
import { formatCount } from "shared";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  PackagingTable,
  type PackagingUnit,
} from "@/components/inventory/detail/packaging-table";
import {
  EditProductDialog,
  type EditCategoryOption,
} from "@/components/inventory/detail/edit-product-dialog";
import {
  AdjustStockDialog,
  type AdjustmentReason,
} from "@/components/inventory/detail/adjust-stock-dialog";
import { Can } from "@/components/auth/can";
import { cn } from "@/lib/utils";

type ProductDetail = {
  header: {
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
  };
  units: PackagingUnit[];
  aliases: Array<{
    alias_id: string;
    alias_text: string;
    language_code: string | null;
    is_display: boolean;
  }>;
};

export default async function ProductDetailPage({
  params,
}: {
  params: Promise<{ shopItemId: string }>;
}) {
  const { shopItemId } = await params;
  const t = await getTranslations("productDetail");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();

  if (!currentShop) {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const [productRes, categoriesRes, shopItemRes, reasonsRes] =
    await Promise.all([
      supabase.rpc("get_shop_item", {
        p_shop_id: currentShop.id,
        p_shop_item_id: shopItemId,
        p_locale: locale,
      }),
      supabase.from("category").select("id, name").order("name"),
      supabase
        .from("shop_item")
        .select("category_id")
        .eq("shop_id", currentShop.id)
        .eq("id", shopItemId)
        .maybeSingle(),
      supabase
        .from("adjustment_reason")
        .select("code, label, is_increase")
        .eq("is_active", true)
        .order("code"),
    ]);
  if (productRes.error) {
    if (productRes.error.message?.includes("not found")) {
      notFound();
    }
    console.error("[product-detail] get_shop_item failed:", productRes.error);
    throw productRes.error;
  }
  const detail = productRes.data as ProductDetail | null;
  if (!detail) notFound();
  const categories: EditCategoryOption[] = (
    (categoriesRes.data ?? []) as Array<{ id: string; name: string }>
  ).map((c) => ({ id: c.id, name: c.name }));
  const currentCategoryId =
    ((shopItemRes.data as { category_id: string | null } | null)?.category_id) ?? null;
  const adjustmentReasons: AdjustmentReason[] = (
    (reasonsRes.data ?? []) as Array<{
      code: string;
      label: string;
      is_increase: boolean | null;
    }>
  ).map((r) => ({ code: r.code, label: r.label, is_increase: r.is_increase }));

  const stock = Number(detail.header.current_stock ?? 0);
  const threshold =
    detail.header.reorder_threshold === null
      ? null
      : Number(detail.header.reorder_threshold);
  const out = stock <= 0;
  const low = !out && threshold !== null && stock <= threshold;

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <Link
        href="/inventory"
        className="text-sm text-muted-foreground hover:text-foreground"
      >
        {t("back")}
      </Link>

      <header className="flex items-start justify-between gap-4">
        <div className="space-y-2">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-semibold tracking-tight">
              {detail.header.display_name}
            </h1>
            {!detail.header.is_active ? (
              <span className="rounded bg-destructive/10 px-2 py-0.5 text-xs font-medium text-destructive">
                {t("inactive")}
              </span>
            ) : null}
          </div>
          {detail.header.category_name ? (
            <p className="text-sm text-muted-foreground">
              {detail.header.category_name}
            </p>
          ) : null}
        </div>
        <div className="flex items-center gap-2">
          <Can capability="inventory.adjustment.post">
            <AdjustStockDialog
              shopId={currentShop.id}
              shopItemId={detail.header.shop_item_id}
              currentStockDisplay={`${formatCount(stock, locale)} ${detail.header.base_unit_label}`}
              unitLabel={detail.header.base_unit_label}
              reasons={adjustmentReasons}
            />
          </Can>
          <Can capability="inventory.product.edit">
            <EditProductDialog
              shopId={currentShop.id}
              shopItemId={detail.header.shop_item_id}
              initialName={detail.header.display_name}
              initialCategoryId={currentCategoryId}
              initialThreshold={
                detail.header.reorder_threshold === null
                  ? null
                  : Number(detail.header.reorder_threshold)
              }
              initialIsActive={detail.header.is_active}
              categories={categories}
            />
          </Can>
        </div>
      </header>

      <Card>
        <CardContent className="pt-6">
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {t("stock.label")}
          </div>
          <div className="mt-1 flex items-baseline gap-3">
            <span
              className={cn(
                "text-3xl font-semibold tabular-nums",
                out && "text-destructive",
                low && "text-amber-600 dark:text-amber-500",
              )}
            >
              {formatCount(stock, locale)} {detail.header.base_unit_label}
            </span>
            {out ? (
              <span className="rounded bg-destructive/10 px-2 py-0.5 text-xs font-medium text-destructive">
                {t("stock.outBadge")}
              </span>
            ) : low ? (
              <span className="rounded bg-amber-500/10 px-2 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400">
                {t("stock.lowBadge", {
                  threshold: formatCount(threshold ?? 0, locale),
                  unit: detail.header.base_unit_label,
                })}
              </span>
            ) : null}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">
            {t("sections.packaging")}
          </CardTitle>
        </CardHeader>
        <CardContent>
          <PackagingTable
            shopId={currentShop.id}
            shopItemId={detail.header.shop_item_id}
            rows={detail.units}
            currencyCode={currentShop.currency_code}
            locale={locale}
            emptyMessage={t("packaging.empty")}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">
            {t("sections.aliases")}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {detail.aliases.length === 0 ? (
            <p className="py-4 text-sm text-muted-foreground">
              {t("aliases.empty")}
            </p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {detail.aliases.map((a) => (
                <span
                  key={a.alias_id}
                  className={cn(
                    "inline-flex items-center gap-1.5 rounded-md border px-2 py-1 text-sm",
                    a.is_display
                      ? "border-primary bg-primary/5"
                      : "border-border bg-background",
                  )}
                >
                  {a.alias_text}
                  {a.language_code ? (
                    <span className="text-xs uppercase text-muted-foreground">
                      {a.language_code}
                    </span>
                  ) : null}
                  {a.is_display ? (
                    <span className="text-xs font-medium text-primary">
                      {t("aliases.displayBadge")}
                    </span>
                  ) : null}
                </span>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
