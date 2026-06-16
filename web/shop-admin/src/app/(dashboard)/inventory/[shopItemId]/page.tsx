// Product detail. Server Component shell that fetches everything and
// hands it to the client ProductEditForm. The form owns the view↔edit
// state machine; this page only handles data + the read-only alias
// list at the bottom.

import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations, getLocale } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { type PackagingUnit } from "@/components/inventory/detail/packaging-table";
import {
  ProductEditForm,
  type CategoryOption,
} from "@/components/inventory/detail/product-edit-form";
import { type AdjustmentReason } from "@/components/inventory/detail/adjust-stock-dialog";
import { type PackagingUnitOption } from "@/components/inventory/detail/add-packaging-dialog";
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

  if (!currentShop) notFound();

  const supabase = await createSupabaseServerClient();
  const [productRes, categoriesRes, shopItemRes, reasonsRes, unitsRes] =
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
      supabase.from("unit").select("code, default_label").order("code"),
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

  const categories: CategoryOption[] = (
    (categoriesRes.data ?? []) as Array<{ id: string; name: string }>
  ).map((c) => ({ id: c.id, name: c.name }));
  const currentCategoryId =
    ((shopItemRes.data as { category_id: string | null } | null)?.category_id) ??
    null;
  const adjustmentReasons: AdjustmentReason[] = (
    (reasonsRes.data ?? []) as Array<{
      code: string;
      label: string;
      is_increase: boolean | null;
    }>
  ).map((r) => ({ code: r.code, label: r.label, is_increase: r.is_increase }));
  const unitOptions: PackagingUnitOption[] = (
    (unitsRes.data ?? []) as Array<{ code: string; default_label: string }>
  ).map((u) => ({ code: u.code, label: u.default_label }));

  const stock = Number(detail.header.current_stock ?? 0);
  const threshold =
    detail.header.reorder_threshold === null
      ? null
      : Number(detail.header.reorder_threshold);

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <Link
        href="/inventory"
        className="text-sm text-muted-foreground hover:text-foreground"
      >
        {t("back")}
      </Link>

      <ProductEditForm
        shopId={currentShop.id}
        shopItemId={detail.header.shop_item_id}
        initialName={detail.header.display_name}
        initialCategoryId={currentCategoryId}
        initialCategoryName={detail.header.category_name}
        initialIsActive={detail.header.is_active}
        initialThreshold={threshold}
        currentStock={stock}
        baseUnitLabel={detail.header.base_unit_label}
        categories={categories}
        packagingRows={detail.units}
        unitOptions={unitOptions}
        adjustmentReasons={adjustmentReasons}
        currencyCode={currentShop.currency_code}
      />

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
