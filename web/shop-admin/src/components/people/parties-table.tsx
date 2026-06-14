// DataTable wrapper for the People module. One instance per type
// (customers / suppliers) — each has its own balance column ("Owes
// you" vs "You owe") and its own empty-state copy.
//
// Client component because: search (filter on every keystroke) +
// DataTable's TanStack state. Server passes the rows in already
// shaped; we don't refetch on the client.

"use client";

import { useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import { Search } from "lucide-react";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable, EmptyState } from "@/components/data-table";
import { Input } from "@/components/ui/input";

export type Party = {
  id: string;
  name: string;
  phone: string | null;
  /** receivable for customers, payable for suppliers — caller picks. */
  balance: number;
};

export function PartiesTable({
  kind,
  rows,
  formatMoney,
}: {
  kind: "customers" | "suppliers";
  rows: Party[];
  formatMoney: (n: number) => string;
}) {
  const t = useTranslations("people");
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter(
      (r) =>
        r.name.toLowerCase().includes(q) ||
        (r.phone ?? "").toLowerCase().includes(q),
    );
  }, [rows, query]);

  const columns = useMemo<ColumnDef<Party>[]>(
    () => [
      {
        accessorKey: "name",
        header: t("columns.name"),
        cell: ({ row }) => (
          <span className="font-medium">{row.original.name}</span>
        ),
      },
      {
        accessorKey: "phone",
        header: t("columns.phone"),
        cell: ({ row }) => (
          <span className="text-muted-foreground">
            {row.original.phone ?? "—"}
          </span>
        ),
      },
      {
        accessorKey: "balance",
        header:
          kind === "customers"
            ? t("columns.receivable")
            : t("columns.payable"),
        cell: ({ row }) => (
          <span
            className={
              row.original.balance > 0
                ? "font-medium tabular-nums"
                : "text-muted-foreground tabular-nums"
            }
          >
            {formatMoney(row.original.balance)}
          </span>
        ),
      },
    ],
    [kind, t, formatMoney],
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
          placeholder={
            kind === "customers"
              ? t("search.customersPlaceholder")
              : t("search.suppliersPlaceholder")
          }
          className="pl-8"
        />
      </div>
      <DataTable
        columns={columns}
        data={filtered}
        empty={
          <EmptyState
            title={
              kind === "customers"
                ? t("empty.customersTitle")
                : t("empty.suppliersTitle")
            }
            description={
              kind === "customers"
                ? t("empty.customersDescription")
                : t("empty.suppliersDescription")
            }
          />
        }
        getRowId={(row) => row.id}
      />
    </div>
  );
}
