// Receive detail line table. Per-line: item, packaging, quantity,
// unit cost, line total. No COGS / margin (that's a sales concept).

"use client";

import { useMemo } from "react";
import { useTranslations } from "next-intl";
import { formatMoney } from "shared";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export type ReceiveLine = {
  line_no: number;
  item_name: string;
  quantity: number;
  unit_label: string;
  packaging_label: string | null;
  unit_amount: number;
  line_total: number;
};

export function LinesTable({
  rows,
  currencyCode,
  locale,
  emptyMessage,
}: {
  rows: ReceiveLine[];
  currencyCode: string;
  locale: string;
  emptyMessage: string;
}) {
  const t = useTranslations("receiveDetail.lines");
  const money = useMemo(
    () => (n: number) => formatMoney(n, currencyCode, locale),
    [currencyCode, locale],
  );

  if (rows.length === 0) {
    return <p className="py-4 text-sm text-muted-foreground">{emptyMessage}</p>;
  }

  return (
    <div className="overflow-hidden rounded-lg border">
      <Table>
        <TableHeader className="bg-muted/30">
          <TableRow>
            <TableHead className="w-12 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("number")}
            </TableHead>
            <TableHead className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("item")}
            </TableHead>
            <TableHead className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("packaging")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("quantity")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("unitCost")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("lineTotal")}
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((r) => (
            <TableRow key={r.line_no}>
              <TableCell className="text-sm text-muted-foreground tabular-nums">
                {r.line_no}
              </TableCell>
              <TableCell className="font-medium">{r.item_name}</TableCell>
              <TableCell className="text-sm text-muted-foreground">
                {r.packaging_label ?? r.unit_label}
              </TableCell>
              <TableCell className="text-right tabular-nums">
                {r.quantity} {r.unit_label}
              </TableCell>
              <TableCell className="text-right tabular-nums">
                {money(r.unit_amount)}
              </TableCell>
              <TableCell className="text-right font-medium tabular-nums">
                {money(r.line_total)}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
