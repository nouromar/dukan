// Aging table — one per side (receivables / payables). Columns:
//   Name | Balance | Last activity | Age bucket
// Sorted by age desc (most overdue first) then by balance desc.
// Buckets follow industry standard: Current (≤30d), 31-60, 61-90, 90+,
// plus a Never bucket for parties with balance but no activity yet
// (e.g. opening-balance only).

"use client";

import { useMemo } from "react";
import { useTranslations } from "next-intl";
import type { ColumnDef } from "@tanstack/react-table";
import { formatMoney } from "shared";
import { DataTable, EmptyState } from "@/components/data-table";
import { cn } from "@/lib/utils";

export type AgingBucket = "current" | "over30" | "over60" | "over90" | "never";

export type AgingRow = {
  party_id: string;
  name: string;
  balance: number;
  /** ISO timestamp of last txn or payment; null if never. */
  last_activity_at: string | null;
  bucket: AgingBucket;
  days_since: number | null;
};

export function AgingTable({
  rows,
  currencyCode,
  locale,
  emptyTitle,
  emptyDescription,
}: {
  rows: AgingRow[];
  currencyCode: string;
  locale: string;
  emptyTitle: string;
  emptyDescription: string;
}) {
  const t = useTranslations("aging");
  const money = (n: number) => formatMoney(n, currencyCode, locale);
  const dateFmt = useMemo(
    () => new Intl.DateTimeFormat(locale, { dateStyle: "medium" }),
    [locale],
  );

  const columns = useMemo<ColumnDef<AgingRow>[]>(
    () => [
      {
        accessorKey: "name",
        header: t("columns.name"),
        cell: ({ row }) => (
          <span className="font-medium">{row.original.name}</span>
        ),
      },
      {
        accessorKey: "balance",
        header: t("columns.balance"),
        cell: ({ row }) => (
          <span className="font-medium tabular-nums">
            {money(row.original.balance)}
          </span>
        ),
      },
      {
        accessorKey: "last_activity_at",
        header: t("columns.lastActivity"),
        cell: ({ row }) => (
          <span className="text-sm text-muted-foreground tabular-nums">
            {row.original.last_activity_at
              ? dateFmt.format(new Date(row.original.last_activity_at))
              : t("noActivityAgo")}
          </span>
        ),
      },
      {
        accessorKey: "bucket",
        header: t("columns.age"),
        cell: ({ row }) => (
          <BucketChip
            bucket={row.original.bucket}
            daysSince={row.original.days_since}
          />
        ),
      },
    ],
    [t, money, dateFmt],
  );

  return (
    <DataTable
      columns={columns}
      data={rows}
      empty={
        <EmptyState
          title={emptyTitle}
          description={emptyDescription}
        />
      }
      getRowId={(row) => row.party_id}
    />
  );
}

function BucketChip({
  bucket,
  daysSince,
}: {
  bucket: AgingBucket;
  daysSince: number | null;
}) {
  const t = useTranslations("aging");
  const labelKey = (
    {
      current: "bucketCurrent",
      over30: "bucketOver30",
      over60: "bucketOver60",
      over90: "bucketOver90",
      never: "bucketNever",
    } as const
  )[bucket];
  // Color escalates with age.
  const tone =
    bucket === "current"
      ? "bg-muted text-muted-foreground"
      : bucket === "over30"
        ? "bg-amber-500/10 text-amber-700 dark:text-amber-400"
        : bucket === "over60"
          ? "bg-orange-500/10 text-orange-700 dark:text-orange-400"
          : "bg-destructive/10 text-destructive";

  return (
    <div className="flex items-center gap-2">
      <span
        className={cn(
          "rounded px-2 py-0.5 text-xs font-medium",
          tone,
        )}
      >
        {t(labelKey)}
      </span>
      {daysSince !== null ? (
        <span className="text-xs text-muted-foreground tabular-nums">
          {t("daysAgo", { days: daysSince })}
        </span>
      ) : null}
    </div>
  );
}
