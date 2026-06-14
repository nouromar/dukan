// Compact list-row variant used for sales/receives/payments under the
// party detail. Not a DataTable — each section is short (typically ≤20
// items) so a vertical stack reads better than a horizontal grid.

"use client";

import { useMemo } from "react";
import { useTranslations } from "next-intl";
import { formatMoney } from "shared";
import { cn } from "@/lib/utils";

export type TxnRow = {
  txn_id: string;
  occurred_at: string;
  total_amount: number;
  paid_amount: number;
  is_voided: boolean;
};

export type PaymentRow = {
  payment_id: string;
  occurred_at: string;
  amount: number;
  /** 'in' = money received from a customer, 'out' = money paid to a supplier. */
  direction: "in" | "out";
};

export function TransactionsList({
  rows,
  currencyCode,
  locale,
  emptyMessage,
}: {
  rows: TxnRow[];
  currencyCode: string;
  locale: string;
  emptyMessage: string;
}) {
  const t = useTranslations("partyDetail");
  const money = (n: number) => formatMoney(n, currencyCode, locale);
  const dateFmt = useMemo(
    () =>
      new Intl.DateTimeFormat(locale, {
        dateStyle: "medium",
        timeStyle: "short",
      }),
    [locale],
  );

  if (rows.length === 0) {
    return (
      <p className="py-4 text-sm text-muted-foreground">{emptyMessage}</p>
    );
  }

  return (
    <ul className="divide-y">
      {rows.map((r) => {
        const onCredit = r.paid_amount < r.total_amount;
        return (
          <li
            key={r.txn_id}
            className="flex items-center justify-between gap-4 py-3 text-sm"
          >
            <div className="flex flex-col">
              <span
                className={cn(
                  "tabular-nums text-muted-foreground",
                  r.is_voided && "line-through",
                )}
              >
                {dateFmt.format(new Date(r.occurred_at))}
              </span>
              {r.is_voided ? (
                <span className="text-xs text-destructive">
                  {t("statusVoided")}
                </span>
              ) : null}
            </div>
            <div className="text-right">
              <div
                className={cn(
                  "font-medium tabular-nums",
                  r.is_voided && "text-muted-foreground line-through",
                )}
              >
                {money(r.total_amount)}
              </div>
              {!r.is_voided && onCredit ? (
                <div className="text-xs text-amber-700 dark:text-amber-400">
                  {money(r.paid_amount)} paid
                </div>
              ) : null}
            </div>
          </li>
        );
      })}
    </ul>
  );
}

export function PaymentsList({
  rows,
  currencyCode,
  locale,
  emptyMessage,
}: {
  rows: PaymentRow[];
  currencyCode: string;
  locale: string;
  emptyMessage: string;
}) {
  const t = useTranslations("partyDetail");
  const money = (n: number) => formatMoney(n, currencyCode, locale);
  const dateFmt = useMemo(
    () =>
      new Intl.DateTimeFormat(locale, {
        dateStyle: "medium",
        timeStyle: "short",
      }),
    [locale],
  );

  if (rows.length === 0) {
    return (
      <p className="py-4 text-sm text-muted-foreground">{emptyMessage}</p>
    );
  }

  return (
    <ul className="divide-y">
      {rows.map((r) => (
        <li
          key={r.payment_id}
          className="flex items-center justify-between gap-4 py-3 text-sm"
        >
          <div className="flex flex-col">
            <span className="tabular-nums text-muted-foreground">
              {dateFmt.format(new Date(r.occurred_at))}
            </span>
            <span
              className={cn(
                "text-xs font-medium",
                r.direction === "in" ? "text-emerald-700 dark:text-emerald-400"
                  : "text-blue-700 dark:text-blue-400",
              )}
            >
              {r.direction === "in" ? t("directionIn") : t("directionOut")}
            </span>
          </div>
          <span className="font-medium tabular-nums">{money(r.amount)}</span>
        </li>
      ))}
    </ul>
  );
}
