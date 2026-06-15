// Sale detail. Header + KPI strip + line table with per-line margin.
//
// Two server calls in parallel:
//   1. get_sale(shop_id, txn_id) — header (party, totals, void status)
//   2. select transaction_line — full line data including cogs_total
//      and shop_item_unit/unit_code/item_name snapshots. RLS on
//      transaction_line gates by shop_id automatically.

import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations, getLocale } from "next-intl/server";
import { formatMoney } from "shared";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  LinesTable,
  type SaleLine,
} from "@/components/sales/detail/lines-table";
import { cn } from "@/lib/utils";

type SaleHeader = {
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

type LineRow = {
  line_no: number;
  item_name_snapshot: string | null;
  quantity: number | string;
  unit_code_snapshot: string | null;
  unit_amount: number | string;
  line_total: number | string;
  cogs_total: number | string | null;
};

export default async function SaleDetailPage({
  params,
}: {
  params: Promise<{ txnId: string }>;
}) {
  const { txnId } = await params;
  const t = await getTranslations("saleDetail");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();

  if (!currentShop) notFound();

  const supabase = await createSupabaseServerClient();
  const [headerRes, linesRes] = await Promise.all([
    supabase.rpc("get_sale", {
      p_shop_id: currentShop.id,
      p_txn_id: txnId,
    }),
    supabase
      .from("transaction_line")
      .select(
        "line_no, item_name_snapshot, quantity, unit_code_snapshot, unit_amount, line_total, cogs_total",
      )
      .eq("shop_id", currentShop.id)
      .eq("transaction_id", txnId)
      .order("line_no", { ascending: true }),
  ]);
  if (headerRes.error) {
    console.error("[sale-detail] get_sale failed:", headerRes.error);
    throw headerRes.error;
  }
  if (linesRes.error) {
    console.error("[sale-detail] lines fetch failed:", linesRes.error);
    throw linesRes.error;
  }

  // get_sale returns a set; either empty (not found) or one row.
  const headers = (headerRes.data as SaleHeader[] | null) ?? [];
  const header = headers[0];
  if (!header) notFound();

  const lines: SaleLine[] = (linesRes.data as LineRow[]).map((r) => ({
    line_no: r.line_no,
    item_name: r.item_name_snapshot ?? "—",
    quantity: Number(r.quantity ?? 0),
    unit_label: r.unit_code_snapshot ?? "",
    unit_amount: Number(r.unit_amount ?? 0),
    line_total: Number(r.line_total ?? 0),
    cogs_total: r.cogs_total === null ? null : Number(r.cogs_total),
  }));

  const total = Number(header.total_amount);
  const paid = Number(header.paid_amount);
  const outstanding = Math.max(0, total - paid);
  const money = (n: number) =>
    formatMoney(n, currentShop.currency_code, locale);
  const occurredAt = new Date(header.occurred_at);

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Link
        href="/sales"
        className="text-sm text-muted-foreground hover:text-foreground"
      >
        {t("back")}
      </Link>

      <header className="space-y-2">
        <div className="flex items-center gap-3">
          <h1
            className={cn(
              "text-3xl font-semibold tracking-tight",
              header.is_voided && "text-muted-foreground line-through",
            )}
          >
            {header.party_name ?? t("walkIn")}
          </h1>
          {header.is_voided ? (
            <span className="rounded bg-destructive/10 px-2 py-0.5 text-xs font-medium text-destructive">
              {t("statusVoided")}
            </span>
          ) : (
            <span className="rounded bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
              {t("statusPosted")}
            </span>
          )}
        </div>
        <p className="text-sm text-muted-foreground tabular-nums">
          {new Intl.DateTimeFormat(locale, {
            dateStyle: "full",
            timeStyle: "short",
          }).format(occurredAt)}
        </p>
      </header>

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Kpi label={t("kpis.total")} value={money(total)} />
        <Kpi label={t("kpis.paid")} value={money(paid)} />
        <Kpi
          label={t("kpis.outstanding")}
          value={money(outstanding)}
          tone={outstanding > 0 ? "warn" : "neutral"}
        />
        <Kpi
          label={t("kpis.method")}
          value={header.payment_method_code ?? "—"}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">
            {t("linesTitle")}
          </CardTitle>
        </CardHeader>
        <CardContent>
          <LinesTable
            rows={lines}
            currencyCode={currentShop.currency_code}
            locale={locale}
            emptyMessage={t("linesEmpty")}
          />
        </CardContent>
      </Card>
    </div>
  );
}

function Kpi({
  label,
  value,
  tone = "neutral",
}: {
  label: string;
  value: string;
  tone?: "neutral" | "warn";
}) {
  return (
    <div className="rounded-lg border p-3">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        {label}
      </div>
      <div
        className={cn(
          "text-xl font-semibold tabular-nums",
          tone === "warn" && "text-amber-700 dark:text-amber-400",
        )}
      >
        {value}
      </div>
    </div>
  );
}
