// Sale-line breakdown. Plain shadcn Table (not DataTable) — no sort,
// no selection, just an ordered list of line_no rows showing each
// item, quantity, unit price, line total, COGS, and margin.
//
// Margin column is the differentiator vs the mobile receipt view:
// the portal user (owner/bookkeeper) cares about profitability per
// line. cogs_total is captured at posting time by post_sale so this
// is the true historical margin, not a moving-average estimate.

"use client";

import { useTranslations } from "next-intl";
import { formatMoney, formatCount } from "shared";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { cn } from "@/lib/utils";

export type SaleLine = {
  line_no: number;
  item_name: string;
  quantity: number;
  unit_label: string;
  unit_amount: number;
  line_total: number;
  cogs_total: number | null;
};

export function LinesTable({
  rows,
  currencyCode,
  locale,
  emptyMessage,
}: {
  rows: SaleLine[];
  currencyCode: string;
  locale: string;
  emptyMessage: string;
}) {
  const t = useTranslations("saleDetail");
  const money = (n: number) => formatMoney(n, currencyCode, locale);
  const count = (n: number) => formatCount(n, locale);

  if (rows.length === 0) {
    return <p className="py-4 text-sm text-muted-foreground">{emptyMessage}</p>;
  }

  return (
    <div className="overflow-hidden rounded-lg border">
      <Table>
        <TableHeader className="bg-muted/30">
          <TableRow>
            <TableHead className="w-12 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.line")}
            </TableHead>
            <TableHead className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.item")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.quantity")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.unitPrice")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.lineTotal")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.cogs")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.margin")}
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((line) => {
            const margin =
              line.cogs_total === null
                ? null
                : line.line_total - line.cogs_total;
            const marginPct =
              margin !== null && line.line_total > 0
                ? Math.round((margin / line.line_total) * 100)
                : null;
            return (
              <TableRow key={line.line_no}>
                <TableCell className="text-sm text-muted-foreground tabular-nums">
                  {line.line_no}
                </TableCell>
                <TableCell className="font-medium">{line.item_name}</TableCell>
                <TableCell className="text-right tabular-nums">
                  {count(line.quantity)} {line.unit_label}
                </TableCell>
                <TableCell className="text-right text-sm text-muted-foreground tabular-nums">
                  {money(line.unit_amount)}
                </TableCell>
                <TableCell className="text-right font-medium tabular-nums">
                  {money(line.line_total)}
                </TableCell>
                <TableCell className="text-right text-sm text-muted-foreground tabular-nums">
                  {line.cogs_total !== null ? (
                    money(line.cogs_total)
                  ) : (
                    <span>{t("marginNoCost")}</span>
                  )}
                </TableCell>
                <TableCell className="text-right tabular-nums">
                  {margin !== null ? (
                    <div className="flex flex-col items-end">
                      <span
                        className={cn(
                          "font-medium",
                          margin > 0
                            ? "text-emerald-700 dark:text-emerald-400"
                            : margin < 0
                              ? "text-destructive"
                              : "text-muted-foreground",
                        )}
                      >
                        {money(margin)}
                      </span>
                      {marginPct !== null ? (
                        <span className="text-xs text-muted-foreground">
                          {t("marginPercent", { percent: marginPct })}
                        </span>
                      ) : null}
                    </div>
                  ) : (
                    <span className="text-muted-foreground">
                      {t("marginNoCost")}
                    </span>
                  )}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );
}
