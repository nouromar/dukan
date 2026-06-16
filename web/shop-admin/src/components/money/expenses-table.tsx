// Expenses list for the Money module. Backed by list_expenses RPC.

"use client";

import { useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import { Search } from "lucide-react";
import type { ColumnDef } from "@tanstack/react-table";
import { formatMoney } from "shared";
import { DataTable, EmptyState } from "@/components/data-table";
import { Input } from "@/components/ui/input";

export type Expense = {
  txn_id: string;
  occurred_at: string;
  category_name: string | null;
  amount: number;
  payment_method_code: string | null;
  notes: string | null;
};

export function ExpensesTable({
  rows,
  currencyCode,
  locale,
}: {
  rows: Expense[];
  currencyCode: string;
  locale: string;
}) {
  const t = useTranslations("money.expenses");
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
      (r.category_name ?? "").toLowerCase().includes(q),
    );
  }, [rows, query]);

  const columns = useMemo<ColumnDef<Expense>[]>(
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
        accessorKey: "category_name",
        header: t("columns.category"),
        cell: ({ row }) =>
          row.original.category_name ? (
            <span className="font-medium">{row.original.category_name}</span>
          ) : (
            <span className="text-muted-foreground">{t("noCategory")}</span>
          ),
      },
      {
        accessorKey: "amount",
        header: t("columns.amount"),
        cell: ({ row }) => (
          <span className="font-medium tabular-nums">
            {money(row.original.amount)}
          </span>
        ),
      },
      {
        accessorKey: "payment_method_code",
        header: t("columns.method"),
        cell: ({ row }) => (
          <span className="text-sm text-muted-foreground">
            {row.original.payment_method_code ?? "—"}
          </span>
        ),
      },
      {
        accessorKey: "notes",
        header: t("columns.notes"),
        cell: ({ row }) =>
          row.original.notes ? (
            <span
              className="text-xs text-muted-foreground"
              title={row.original.notes}
            >
              {row.original.notes.length > 40
                ? row.original.notes.slice(0, 40) + "…"
                : row.original.notes}
            </span>
          ) : null,
      },
    ],
    [t, money, dateFmt],
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
          placeholder={t("search")}
          className="pl-8"
        />
      </div>
      <DataTable
        columns={columns}
        data={filtered}
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
