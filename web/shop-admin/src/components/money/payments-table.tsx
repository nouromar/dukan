// Payments list for the Money module. Backed by list_payments RPC.
// Direction column distinguishes inbound (customer paid us) from
// outbound (we paid a supplier).

"use client";

import { useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import { Search } from "lucide-react";
import type { ColumnDef } from "@tanstack/react-table";
import { formatMoney } from "shared";
import { DataTable, EmptyState } from "@/components/data-table";
import { Input } from "@/components/ui/input";

export type Payment = {
  payment_id: string;
  occurred_at: string;
  party_name: string | null;
  amount: number;
  direction: "I" | "O";
  payment_method_code: string | null;
  notes: string | null;
};

export function PaymentsTable({
  rows,
  currencyCode,
  locale,
}: {
  rows: Payment[];
  currencyCode: string;
  locale: string;
}) {
  const t = useTranslations("money.payments");
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

  const columns = useMemo<ColumnDef<Payment>[]>(
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
        header: t("columns.party"),
        cell: ({ row }) =>
          row.original.party_name ? (
            <span className="font-medium">{row.original.party_name}</span>
          ) : (
            <span className="text-muted-foreground">{t("noParty")}</span>
          ),
      },
      {
        accessorKey: "direction",
        header: t("columns.direction"),
        cell: ({ row }) => (
          <span
            className={
              row.original.direction === "I"
                ? "rounded bg-emerald-500/10 px-2 py-0.5 text-xs font-medium text-emerald-700 dark:text-emerald-400"
                : "rounded bg-blue-500/10 px-2 py-0.5 text-xs font-medium text-blue-700 dark:text-blue-400"
            }
          >
            {row.original.direction === "I"
              ? t("directionIn")
              : t("directionOut")}
          </span>
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
        getRowId={(row) => row.payment_id}
      />
    </div>
  );
}
