// Audit log table. Read-only feed of the last N events for the
// current shop. Time column shows compact ISO date+time in the user's
// locale (no relative-time formatting yet — adds Intl complexity, can
// come later).

"use client";

import { useMemo } from "react";
import { useTranslations } from "next-intl";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable, EmptyState } from "@/components/data-table";

export type AuditEntry = {
  id: string;
  occurred_at: string;
  action_code: string;
  action_label: string;
  entity_type: string;
  entity_id: string | null;
  source: string;
  /**
   * 'you' = actor_user_id matched the current viewer
   * 'system' = actor_user_id was null (RPC / cron / impersonation)
   * 'other' = a different user (display name resolution pending —
   * needs a privileged view over auth.users that we haven't added)
   */
  actor: "you" | "system" | "other";
  actor_id_short: string | null;
};

const SOURCE_KEYS: Record<string, string> = {
  mobile: "mobile",
  shop_admin_web: "shop_admin_web",
  system_admin_web: "system_admin_web",
  rpc: "rpc",
  system: "system",
};

export function AuditTable({
  rows,
  locale,
}: {
  rows: AuditEntry[];
  locale: string;
}) {
  const t = useTranslations("audit");

  const fmt = useMemo(
    () =>
      new Intl.DateTimeFormat(locale, {
        dateStyle: "medium",
        timeStyle: "short",
      }),
    [locale],
  );

  const columns = useMemo<ColumnDef<AuditEntry>[]>(
    () => [
      {
        accessorKey: "occurred_at",
        header: t("columns.time"),
        cell: ({ row }) => (
          <span className="text-sm tabular-nums text-muted-foreground">
            {fmt.format(new Date(row.original.occurred_at))}
          </span>
        ),
      },
      {
        accessorKey: "action_label",
        header: t("columns.action"),
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="font-medium">
              {row.original.action_label}
            </span>
            <span className="text-xs text-muted-foreground">
              {row.original.action_code}
            </span>
          </div>
        ),
      },
      {
        accessorKey: "actor",
        header: t("columns.actor"),
        cell: ({ row }) => {
          const label =
            row.original.actor === "you"
              ? t("actorYou")
              : row.original.actor === "system"
                ? t("actorSystem")
                : t("actorOther");
          return (
            <div className="flex flex-col text-sm">
              <span
                className={
                  row.original.actor === "you"
                    ? "font-medium text-primary"
                    : "text-foreground"
                }
              >
                {label}
              </span>
              {row.original.actor_id_short ? (
                <span className="font-mono text-xs text-muted-foreground">
                  {row.original.actor_id_short}
                </span>
              ) : null}
            </div>
          );
        },
      },
      {
        accessorKey: "entity_type",
        header: t("columns.entity"),
        cell: ({ row }) => (
          <span className="text-sm">
            {row.original.entity_type}
            {row.original.entity_id ? (
              <span className="ml-2 font-mono text-xs text-muted-foreground">
                {row.original.entity_id.slice(0, 8)}
              </span>
            ) : null}
          </span>
        ),
      },
      {
        accessorKey: "source",
        header: t("columns.source"),
        cell: ({ row }) => {
          const key = SOURCE_KEYS[row.original.source] ?? "system";
          return (
            <span className="rounded bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
              {t(`sources.${key}` as "sources.mobile")}
            </span>
          );
        },
      },
    ],
    [t, fmt],
  );

  return (
    <DataTable
      columns={columns}
      data={rows}
      empty={
        <EmptyState
          title={t("empty.title")}
          description={t("empty.description")}
        />
      }
      getRowId={(row) => row.id}
    />
  );
}
