// P&L panel for the Money module. Renders this-month KPI cards +
// last-6-months breakdown table. Reads from v_monthly_profit view.
//
// Pure server-rendered presentation: data is fetched in /money/page.tsx
// and shaped here. No interactivity yet (period selector deferred).

import { useTranslations } from "next-intl";
import { formatMoney } from "shared";
import { Card, CardContent } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { EmptyState } from "@/components/data-table";
import { cn } from "@/lib/utils";

export type MonthlyProfitRow = {
  local_month: string; // YYYY-MM-01
  revenue: number;
  cogs_total: number;
  gross_profit: number;
  expense_total: number;
  net_profit: number;
};

export function ProfitPanel({
  rows,
  currencyCode,
  locale,
}: {
  /** Sorted desc by local_month (most recent first). */
  rows: MonthlyProfitRow[];
  currencyCode: string;
  locale: string;
}) {
  const t = useTranslations("money.profit");
  const money = (n: number) => formatMoney(n, currencyCode, locale);
  const monthFmt = new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "long",
  });

  if (rows.length === 0) {
    return (
      <EmptyState
        title={t("empty.title")}
        description={t("empty.description")}
      />
    );
  }

  // The first row is the most recent month (this month).
  const current = rows[0];

  return (
    <div className="space-y-6">
      <div>
        <div className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {t("thisMonth")} — {monthFmt.format(new Date(current.local_month))}
        </div>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          <Kpi label={t("kpis.revenue")} value={money(current.revenue)} />
          <Kpi label={t("kpis.cogs")} value={money(current.cogs_total)} />
          <Kpi
            label={t("kpis.grossProfit")}
            value={money(current.gross_profit)}
            tone={current.gross_profit >= 0 ? "good" : "bad"}
          />
          <Kpi label={t("kpis.expenses")} value={money(current.expense_total)} />
          <Kpi
            label={t("kpis.netProfit")}
            value={money(current.net_profit)}
            tone={current.net_profit >= 0 ? "good" : "bad"}
          />
        </div>
      </div>

      {rows.length > 1 ? (
        <div>
          <div className="mb-2 text-sm font-medium">{t("history")}</div>
          <div className="overflow-hidden rounded-lg border">
            <Table>
              <TableHeader className="bg-muted/30">
                <TableRow>
                  <TableHead className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {t("columns.month")}
                  </TableHead>
                  <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {t("columns.revenue")}
                  </TableHead>
                  <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {t("columns.cogs")}
                  </TableHead>
                  <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {t("columns.gross")}
                  </TableHead>
                  <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {t("columns.expenses")}
                  </TableHead>
                  <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {t("columns.net")}
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((r) => (
                  <TableRow key={r.local_month}>
                    <TableCell className="font-medium">
                      {monthFmt.format(new Date(r.local_month))}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {money(r.revenue)}
                    </TableCell>
                    <TableCell className="text-right text-sm text-muted-foreground tabular-nums">
                      {money(r.cogs_total)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {money(r.gross_profit)}
                    </TableCell>
                    <TableCell className="text-right text-sm text-muted-foreground tabular-nums">
                      {money(r.expense_total)}
                    </TableCell>
                    <TableCell
                      className={cn(
                        "text-right font-medium tabular-nums",
                        r.net_profit < 0
                          ? "text-destructive"
                          : r.net_profit > 0
                            ? "text-emerald-700 dark:text-emerald-400"
                            : "text-muted-foreground",
                      )}
                    >
                      {money(r.net_profit)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </div>
      ) : null}
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
  tone?: "neutral" | "good" | "bad";
}) {
  return (
    <Card>
      <CardContent className="space-y-1 pt-6">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {label}
        </div>
        <div
          className={cn(
            "text-xl font-semibold tabular-nums",
            tone === "good" && "text-emerald-700 dark:text-emerald-400",
            tone === "bad" && "text-destructive",
          )}
        >
          {value}
        </div>
      </CardContent>
    </Card>
  );
}
