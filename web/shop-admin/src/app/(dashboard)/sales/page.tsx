// Sales history. Last 50 sales for the current shop via list_sales RPC.
// Voided pairs collapse to a single row (the RPC's LEFT JOIN handles
// it). Pagination cursor (p_before) is plumbed at the RPC level but
// not surfaced in the UI yet — 50 is enough for v1.

import { getTranslations, getLocale } from "next-intl/server";
import { historyPageLimit } from "shared";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SalesTable, type Sale } from "@/components/sales/sales-table";
import {
  SalesFilters,
  type PartyOption,
} from "@/components/sales/sales-filters";
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

export default async function SalesPage({
  searchParams,
}: {
  searchParams: Promise<{ from?: string; to?: string; party?: string }>;
}) {
  const t = await getTranslations("sales");
  const locale = await getLocale();
  const { currentShop, capabilities } = await getCurrentShop();
  const canExport = capabilities.includes("sales.export");
  const { from, to, party: partyId } = await searchParams;

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
  // Date strings from the form are 'YYYY-MM-DD'; Postgres parses
  // those as midnight in its session timezone. Good enough for the
  // filter granularity; server-side timezone handling lives in the
  // RPC's per-row local_date computation.
  const [{ data, error }, partiesRes] = await Promise.all([
    supabase.rpc("list_sales", {
      p_shop_id: currentShop.id,
      p_limit: historyPageLimit,
      p_date_from: from || null,
      p_date_to: to || null,
      p_party_id: partyId || null,
    }),
    // Customer list for the party-filter dropdown. Cap at active rows.
    supabase
      .from("party")
      .select("id, name, type_id, party_type!inner(code)")
      .eq("shop_id", currentShop.id)
      .eq("is_active", true)
      .eq("party_type.code", "customer")
      .order("name"),
  ]);
  if (error) {
    console.error("[sales] list_sales failed:", JSON.stringify(error));
    throw error;
  }
  const parties: PartyOption[] = (
    (partiesRes.data ?? []) as Array<{ id: string; name: string }>
  ).map((p) => ({ id: p.id, name: p.name }));

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
      <SalesFilters
        parties={parties}
        initialFrom={from ?? null}
        initialTo={to ?? null}
        initialPartyId={partyId ?? null}
      />
      <SalesTable
        rows={sales}
        currencyCode={currentShop.currency_code}
        locale={locale}
      />
    </div>
  );
}
