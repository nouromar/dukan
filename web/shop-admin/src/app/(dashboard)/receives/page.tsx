// Receives history. Mirrors /sales — list_receives RPC, voided pairs
// collapse to one row, party_id=null shown as "Unknown supplier".

import Link from "next/link";
import { getTranslations, getLocale } from "next-intl/server";
import { Plus } from "lucide-react";
import { historyPageLimit } from "shared";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { buttonVariants } from "@/components/ui/button";
import { ReceivesTable, type Receive } from "@/components/receives/receives-table";
import {
  ReceivesFilters,
  type PartyOption,
} from "@/components/receives/receives-filters";
import { ExportCsvButton } from "@/components/shared/export-csv-button";
import { Can } from "@/components/auth/can";
import { cn } from "@/lib/utils";

type ReceiveRow = {
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

export default async function ReceivesPage({
  searchParams,
}: {
  searchParams: Promise<{ from?: string; to?: string; party?: string }>;
}) {
  const t = await getTranslations("receives");
  const locale = await getLocale();
  const { currentShop, capabilities } = await getCurrentShop();
  const canExport = capabilities.includes("receive.history.view");
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
  const [{ data, error }, partiesRes] = await Promise.all([
    supabase.rpc("list_receives", {
      p_shop_id: currentShop.id,
      p_limit: historyPageLimit,
      p_date_from: from || null,
      p_date_to: to || null,
      p_party_id: partyId || null,
    }),
    // Supplier list for the party-filter dropdown.
    supabase
      .from("party")
      .select("id, name, type_id, party_type!inner(code)")
      .eq("shop_id", currentShop.id)
      .eq("is_active", true)
      .eq("party_type.code", "supplier")
      .order("name"),
  ]);
  if (error) {
    console.error("[receives] list_receives failed:", JSON.stringify(error));
    throw error;
  }
  const parties: PartyOption[] = (
    (partiesRes.data ?? []) as Array<{ id: string; name: string }>
  ).map((p) => ({ id: p.id, name: p.name }));

  const rows = (data as ReceiveRow[] | null) ?? [];
  const receives: Receive[] = rows.map((r) => ({
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
            {receives.length === historyPageLimit
              ? `${historyPageLimit}+`
              : receives.length}
          </span>
        </div>
        <div className="flex items-center gap-3">
          {canExport ? <ExportCsvButton href="/api/export/receives" /> : null}
          <Can capability="receive.post">
            <Link
              href="/receives/new"
              className={cn(buttonVariants({ size: "sm" }), "gap-2")}
            >
              <Plus className="size-4" aria-hidden />
              {t("recordButton")}
            </Link>
          </Can>
        </div>
      </div>
      <ReceivesFilters
        parties={parties}
        initialFrom={from ?? null}
        initialTo={to ?? null}
        initialPartyId={partyId ?? null}
      />
      <ReceivesTable
        rows={receives}
        currencyCode={currentShop.currency_code}
        locale={locale}
      />
    </div>
  );
}
