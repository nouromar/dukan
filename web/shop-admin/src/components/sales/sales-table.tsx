// Sales history table. Reads list_sales output + renders columns.
// Voided sales are visually crossed-out + badged; the underlying
// reverses_transaction_id pair is collapsed to a single row by the
// RPC's LEFT JOIN sales r on r.reverses_transaction_id = o.id.
//
// Read-only for now. Row click → sale detail (#276) wired once that
// page exists.

"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Search } from "lucide-react";
import type { ColumnDef } from "@tanstack/react-table";
import { formatMoney } from "shared";
import { DataTable, EmptyState } from "@/components/data-table";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

export type Sale = {
  txn_id: string;
  occurred_at: string;
  party_name: string | null;
  total_amount: number;
  paid_amount: number;
  is_voided: boolean;
};

export function SalesTable({
  rows,
  currencyCode,
  locale,
}: {
  rows: Sale[];
  currencyCode: string;
  locale: string;
}) {
  const t = useTranslations("sales");
  const router = useRouter();
  const [query, setQuery] = useState("");

  const money = (n: number) => formatMoney(n, currencyCode, locale);
  const dateFmt = useMemo(
    () =>
      new Intl.DateTimeFormat(locale, {
        dateStyle: "medium",
        timeStyle: "short",
      }),
    [locale],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) =>
      (r.party_name ?? "").toLowerCase().includes(q),
    );
  }, [rows, query]);

  const columns = useMemo<ColumnDef<Sale>[]>(
    () => [
      {
        accessorKey: "occurred_at",
        header: t("columns.when"),
        cell: ({ row }) => (
          <span className="text-sm tabular-nums text-muted-foreground">
            {dateFmt.format(new Date(row.original.occurred_at))}
          </span>
        ),
      },
      {
        accessorKey: "party_name",
        header: t("columns.customer"),
        cell: ({ row }) => (
          <span
            className={cn(
              "font-medium",
              row.original.is_voided && "text-muted-foreground line-through",
            )}
          >
            {row.original.party_name ?? (
              <span className="text-muted-foreground italic">
                {t("walkIn")}
              </span>
            )}
          </span>
        ),
      },
      {
        accessorKey: "total_amount",
        header: t("columns.total"),
        cell: ({ row }) => (
          <span
            className={cn(
              "font-medium tabular-nums",
              row.original.is_voided && "text-muted-foreground line-through",
            )}
          >
            {money(row.original.total_amount)}
          </span>
        ),
      },
      {
        accessorKey: "paid_amount",
        header: t("columns.paid"),
        cell: ({ row }) => {
          const onCredit =
            row.original.paid_amount < row.original.total_amount;
          return (
            <div className="flex items-center gap-2 tabular-nums">
              <span
                className={cn(
                  row.original.is_voided && "text-muted-foreground line-through",
                )}
              >
                {money(row.original.paid_amount)}
              </span>
              {onCredit && !row.original.is_voided ? (
                <span className="rounded bg-amber-500/10 px-1.5 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400">
                  {t("creditMarker")}
                </span>
              ) : null}
            </div>
          );
        },
      },
      {
        accessorKey: "is_voided",
        header: t("columns.status"),
        cell: ({ row }) =>
          row.original.is_voided ? (
            <span className="rounded bg-destructive/10 px-2 py-0.5 text-xs font-medium text-destructive">
              {t("statusVoided")}
            </span>
          ) : (
            <span className="rounded bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
              {t("statusPosted")}
            </span>
          ),
      },
    ],
    [t, currencyCode, locale, dateFmt, money],
  );

  return (
    <div className="space-y-4">
      <div className="relative max-w-sm">
        <Search
          className="pointer-events-none absolute left-2.5 top-2.5 size-4 text-muted-foreground"
          aria-hidden
        />
        <Input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={t("search.placeholder")}
          className="pl-8"
        />
      </div>
      <DataTable
        columns={columns}
        data={filtered}
        onRowClick={(row) => router.push(`/sales/${row.txn_id}`)}
        empty={
          <EmptyState
            title={t("empty.title")}
            description={t("empty.description")}
          />
        }
        getRowId={(row) => row.txn_id}
      />
    </div>
  );
}
