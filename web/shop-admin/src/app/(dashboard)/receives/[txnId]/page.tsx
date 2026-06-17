// Receive detail. Mirrors /sales/[txnId] — header + KPI strip + line
// table. No COGS / margin (those are sales concepts). Owner-only Void.

import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations, getLocale } from "next-intl/server";
import { formatMoney } from "shared";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  LinesTable,
  type ReceiveLine,
} from "@/components/receives/detail/lines-table";
import { VoidReceiveButton } from "@/components/receives/detail/void-receive-button";
import { Can } from "@/components/auth/can";
import { cn } from "@/lib/utils";

type ReceiveHeader = {
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
  item_id: string | null;
  shop_item_unit_id: string | null;
  item_name: string;
  quantity: number | string;
  unit_label: string;
  unit_amount: number | string;
  line_total: number | string;
  packaging_label: string | null;
};

export default async function ReceiveDetailPage({
  params,
}: {
  params: Promise<{ txnId: string }>;
}) {
  const { txnId } = await params;
  const t = await getTranslations("receiveDetail");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();

  if (!currentShop) notFound();

  const supabase = await createSupabaseServerClient();
  const [headerRes, linesRes] = await Promise.all([
    supabase.rpc("get_receive", {
      p_shop_id: currentShop.id,
      p_txn_id: txnId,
    }),
    supabase.rpc("get_receive_lines", {
      p_shop_id: currentShop.id,
      p_txn_id: txnId,
    }),
  ]);
  if (headerRes.error) {
    console.error("[receive-detail] get_receive failed:", headerRes.error);
    throw headerRes.error;
  }
  if (linesRes.error) {
    console.error(
      "[receive-detail] get_receive_lines failed:",
      linesRes.error,
    );
    throw linesRes.error;
  }

  const headers = (headerRes.data as ReceiveHeader[] | null) ?? [];
  const header = headers[0];
  if (!header) notFound();

  const lines: ReceiveLine[] = (
    (linesRes.data ?? []) as LineRow[]
  ).map((r) => ({
    line_no: r.line_no,
    item_name: r.item_name,
    quantity: Number(r.quantity ?? 0),
    unit_label: r.unit_label,
    packaging_label: r.packaging_label,
    unit_amount: Number(r.unit_amount ?? 0),
    line_total: Number(r.line_total ?? 0),
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
        href="/receives"
        className="text-sm text-muted-foreground hover:text-foreground"
      >
        {t("back")}
      </Link>

      <header className="flex items-start justify-between gap-4">
        <div className="space-y-2">
          <div className="flex items-center gap-3">
            <h1
              className={cn(
                "text-3xl font-semibold tracking-tight",
                header.is_voided && "text-muted-foreground line-through",
              )}
            >
              {header.party_name ?? t("unknownSupplier")}
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
        </div>
        {!header.is_voided ? (
          <Can capability="receive.void">
            <VoidReceiveButton shopId={currentShop.id} txnId={txnId} />
          </Can>
        ) : null}
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
