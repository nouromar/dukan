// Sales history. Last 50 sales for the current shop via list_sales RPC.
// Voided pairs collapse to a single row (the RPC's LEFT JOIN handles
// it). Pagination cursor (p_before) is plumbed at the RPC level but
// not surfaced in the UI yet — 50 is enough for v1.

import { getTranslations, getLocale } from "next-intl/server";
import { historyPageLimit } from "shared";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SalesTable, type Sale } from "@/components/sales/sales-table";
import { ExportCsvButton } from "@/components/shared/export-csv-button";

type SaleRow = {
  txn_id: string;
  occurred_at: string;
  posted_at: string;
  party_id: string | null;
  party_name: string | null;
  total_amount: number | string;
  paid_amount: number | string;
  payment_method_code: string | null;
  is_voided: boolean;
  reversal_txn_id: string | null;
  voided_at: string | null;
};

export default async function SalesPage() {
  const t = await getTranslations("sales");
  const locale = await getLocale();
  const { currentShop, capabilities } = await getCurrentShop();
  const canExport = capabilities.includes("sales.export");

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
  const { data, error } = await supabase.rpc("list_sales", {
    p_shop_id: currentShop.id,
    p_limit: historyPageLimit,
  });
  if (error) {
    console.error("[sales] list_sales failed:", JSON.stringify(error));
    throw error;
  }

  const rows = (data as SaleRow[] | null) ?? [];
  const sales: Sale[] = rows.map((r) => ({
    txn_id: r.txn_id,
    occurred_at: r.occurred_at,
    party_name: r.party_name,
    total_amount: Number(r.total_amount ?? 0),
    paid_amount: Number(r.paid_amount ?? 0),
    is_voided: r.is_voided,
  }));

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-baseline gap-3">
          <h1 className="text-2xl font-semibold tracking-tight">
            {currentShop.name}
          </h1>
          <span className="text-sm text-muted-foreground">
            {sales.length === historyPageLimit ? `${historyPageLimit}+` : sales.length}
          </span>
        </div>
        {canExport ? <ExportCsvButton href="/api/export/sales" /> : null}
      </div>
      <SalesTable
        rows={sales}
        currencyCode={currentShop.currency_code}
        locale={locale}
      />
    </div>
  );
}
