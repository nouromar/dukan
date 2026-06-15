// Client-side wrapper around DataTable for the Products list. Drives:
//   - search input that filters in-memory (131 rows is small; we can
//     swap to server-side search via list_shop_items(p_query) later
//     when shops grow real catalogs)
//   - stock badge: red "Out" when current_stock <= 0; amber "Low"
//     when current_stock <= reorder_threshold (threshold may be null,
//     in which case Low never triggers)
//   - dim missing prices to "—"
//
// Read-only for now. Inline edits for reorder_threshold + sale_price
// are tracked as #286.

"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Search, DollarSign, AlertTriangle } from "lucide-react";
import type { ColumnDef } from "@tanstack/react-table";
import { formatMoney, formatCount } from "shared";
import { DataTable, EmptyState, type BulkAction } from "@/components/data-table";
import { Input } from "@/components/ui/input";
import { useShopContext } from "@/lib/shop-context";
import { cn } from "@/lib/utils";
import {
  BulkEditDialog,
  type BulkVariant,
} from "./bulk-edit-dialog";

export type Product = {
  shop_item_id: string;
  display_name: string;
  category_name: string | null;
  base_unit_code: string;
  base_unit_label: string;
  current_stock: number;
  reorder_threshold: number | null;
  default_sale_price: number | null;
  is_active: boolean;
};

export function ProductsTable({
  rows,
  currencyCode,
  locale,
}: {
  rows: Product[];
  // Funcs can't cross the server→client boundary in RSC. Pass the
  // currency code + locale and let this component call the shared
  // formatters directly.
  currencyCode: string;
  locale: string;
}) {
  const t = useTranslations("inventory");
  const tBulk = useTranslations("inventory.bulk");
  const router = useRouter();
  const { currentShop, capabilities } = useShopContext();
  const [query, setQuery] = useState("");
  const [bulkVariant, setBulkVariant] = useState<BulkVariant | null>(null);
  const [selectedIdsForDialog, setSelectedIdsForDialog] = useState<string[]>(
    [],
  );

  const canBulkEdit = capabilities.has("inventory.product.bulk_edit");

  const money = (n: number) => formatMoney(n, currencyCode, locale);
  const count = (n: number) => formatCount(n, locale);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) =>
      r.display_name.toLowerCase().includes(q),
    );
  }, [rows, query]);

  const columns = useMemo<ColumnDef<Product>[]>(
    () => [
      {
        accessorKey: "display_name",
        header: t("columns.name"),
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span
              className={cn(
                "font-medium",
                !row.original.is_active && "text-muted-foreground line-through",
              )}
            >
              {row.original.display_name}
            </span>
          </div>
        ),
      },
      {
        accessorKey: "category_name",
        header: t("columns.category"),
        cell: ({ row }) => (
          <span className="text-sm text-muted-foreground">
            {row.original.category_name ?? "—"}
          </span>
        ),
      },
      {
        accessorKey: "current_stock",
        header: t("columns.stock"),
        cell: ({ row }) => {
          const stock = row.original.current_stock;
          const threshold = row.original.reorder_threshold;
          const out = stock <= 0;
          const low = !out && threshold !== null && stock <= threshold;
          return (
            <div className="flex items-center gap-2 tabular-nums">
              <span
                className={cn(
                  "font-medium",
                  out && "text-destructive",
                  low && "text-amber-600 dark:text-amber-500",
                )}
              >
                {count(stock)} {row.original.base_unit_label}
              </span>
              {out ? (
                <span className="rounded bg-destructive/10 px-1.5 py-0.5 text-xs font-medium text-destructive">
                  {t("outOfStockBadge")}
                </span>
              ) : low ? (
                <span className="rounded bg-amber-500/10 px-1.5 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400">
                  {t("lowStockBadge")}
                </span>
              ) : null}
            </div>
          );
        },
      },
      {
        accessorKey: "reorder_threshold",
        header: t("columns.threshold"),
        cell: ({ row }) => (
          <span className="text-sm text-muted-foreground tabular-nums">
            {row.original.reorder_threshold !== null
              ? `${count(row.original.reorder_threshold)} ${row.original.base_unit_label}`
              : "—"}
          </span>
        ),
      },
      {
        accessorKey: "default_sale_price",
        header: t("columns.price"),
        cell: ({ row }) =>
          row.original.default_sale_price !== null ? (
            <span className="font-medium tabular-nums">
              {money(row.original.default_sale_price)}
            </span>
          ) : (
            <span className="text-muted-foreground">{t("noPrice")}</span>
          ),
      },
    ],
    [t, currencyCode, locale],
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
        onRowClick={(row) => router.push(`/inventory/${row.shop_item_id}`)}
        empty={
          <EmptyState
            title={t("empty.title")}
            description={t("empty.description")}
          />
        }
        getRowId={(row) => row.shop_item_id}
        bulkActions={
          canBulkEdit && currentShop
            ? (selected): BulkAction[] => {
                const ids = selected.map((s) => s.shop_item_id);
                return [
                  {
                    id: "bulk-price",
                    label: tBulk("setPrice"),
                    icon: DollarSign,
                    onClick: () => {
                      setSelectedIdsForDialog(ids);
                      setBulkVariant("price");
                    },
                  },
                  {
                    id: "bulk-threshold",
                    label: tBulk("setThreshold"),
                    icon: AlertTriangle,
                    variant: "outline",
                    onClick: () => {
                      setSelectedIdsForDialog(ids);
                      setBulkVariant("threshold");
                    },
                  },
                ];
              }
            : undefined
        }
      />
      {currentShop && bulkVariant !== null ? (
        <BulkEditDialog
          variant={bulkVariant}
          open={bulkVariant !== null}
          onOpenChange={(open) => {
            if (!open) setBulkVariant(null);
          }}
          shopId={currentShop.id}
          shopItemIds={selectedIdsForDialog}
        />
      ) : null}
    </div>
  );
}
