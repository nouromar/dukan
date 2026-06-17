// Record-receive page. Server component pre-fetches everything the
// form needs in one round trip:
//   * Active suppliers (party_type=supplier).
//   * Active products (display name resolved via list_shop_items).
//   * Active packagings per product, with packaging_label snapshot,
//     conversion_to_base, is_default_receive, and the most recent
//     last_cost we have for that packaging.
//
// All shipped to the client as a flat array; the form filters
// in-memory when the user picks a product. Cheap for v1 catalog
// sizes (≤ a few hundred packagings).

import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations, getLocale } from "next-intl/server";
import { Card, CardContent } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  RecordReceiveForm,
  type SupplierOption,
  type ProductOption,
  type PackagingOption,
} from "@/components/receives/record-receive-form";

export default async function NewReceivePage() {
  const t = await getTranslations("recordReceive");
  const locale = await getLocale();
  const { currentShop, capabilities } = await getCurrentShop();
  if (!currentShop) notFound();
  if (!capabilities.includes("receive.post")) {
    return (
      <div className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-xl font-medium">{t("forbidden.title")}</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          {t("forbidden.description")}
        </p>
      </div>
    );
  }

  const supabase = await createSupabaseServerClient();
  const [suppliersRes, productsRes, packagingsRes] = await Promise.all([
    supabase
      .from("party")
      .select("id, name, party_type!inner(code)")
      .eq("shop_id", currentShop.id)
      .eq("is_active", true)
      .eq("party_type.code", "supplier")
      .order("name"),
    supabase.rpc("list_shop_items", {
      p_shop_id: currentShop.id,
      p_locale: locale,
    }),
    // Per-packaging fetch. We need conversion + base_unit_code +
    // packaging label snapshot. Joining via shop_item gives the base
    // unit for the packaging label rendering.
    supabase
      .from("shop_item_unit")
      .select(
        "id, shop_item_id, unit_code, conversion_to_base, is_default_receive, is_active, last_cost, shop_item!inner(id, base_unit_code, is_active)",
      )
      .eq("shop_id", currentShop.id)
      .eq("is_active", true)
      .eq("shop_item.is_active", true),
  ]);

  for (const r of [suppliersRes, productsRes, packagingsRes]) {
    if (r.error) {
      console.error("[record-receive] fetch failed:", r.error);
      throw r.error;
    }
  }

  const suppliers: SupplierOption[] = (
    (suppliersRes.data ?? []) as Array<{ id: string; name: string }>
  ).map((s) => ({ id: s.id, name: s.name }));

  const products: ProductOption[] = (
    (productsRes.data ?? []) as Array<{
      shop_item_id: string;
      display_name: string;
      is_active: boolean;
    }>
  )
    .filter((p) => p.is_active)
    .map((p) => ({ id: p.shop_item_id, displayName: p.display_name }));

  type PackagingRow = {
    id: string;
    shop_item_id: string;
    unit_code: string;
    conversion_to_base: number | string;
    is_default_receive: boolean;
    last_cost: number | string | null;
    // PostgREST returns embedded relations as arrays even for a
    // many-to-one FK; we always look at the first element.
    shop_item: Array<{ base_unit_code: string }>;
  };
  const packagings: PackagingOption[] = (
    (packagingsRes.data ?? []) as unknown as PackagingRow[]
  ).map((u) => {
    const conv = Number(u.conversion_to_base);
    const baseUnit = u.shop_item[0]?.base_unit_code ?? "";
    return {
      shopItemUnitId: u.id,
      shopItemId: u.shop_item_id,
      unitCode: u.unit_code,
      unitLabel: u.unit_code,
      packagingLabel:
        conv === 1 ? u.unit_code : `${conv} ${baseUnit} ${u.unit_code}`,
      conversionToBase: conv,
      isDefaultReceive: u.is_default_receive,
      lastCost: u.last_cost === null ? null : Number(u.last_cost),
    };
  });

  if (suppliers.length === 0) {
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <Link
          href="/receives"
          className="text-sm text-muted-foreground hover:text-foreground"
        >
          {t("back")}
        </Link>
        <Card>
          <CardContent className="space-y-2 py-12 text-center">
            <h1 className="text-lg font-semibold">
              {t("noSuppliers.title")}
            </h1>
            <p className="text-sm text-muted-foreground">
              {t("noSuppliers.description")}
            </p>
            <Link
              href="/people?type=supplier"
              className="inline-block pt-2 text-sm font-medium text-primary hover:underline"
            >
              {t("noSuppliers.cta")}
            </Link>
          </CardContent>
        </Card>
      </div>
    );
  }

  // Today in the shop's locale, formatted as YYYY-MM-DD for the date
  // input. Computed server-side so the form bundle stays deterministic.
  const todayIso = new Date().toISOString().slice(0, 10);

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div className="flex items-center justify-between">
        <Link
          href="/receives"
          className="text-sm text-muted-foreground hover:text-foreground"
        >
          {t("back")}
        </Link>
        <h1 className="text-xl font-semibold tracking-tight">{t("title")}</h1>
      </div>
      <RecordReceiveForm
        shopId={currentShop.id}
        suppliers={suppliers}
        products={products}
        packagings={packagings}
        currencyCode={currentShop.currency_code}
        locale={locale}
        todayIso={todayIso}
      />
    </div>
  );
}
