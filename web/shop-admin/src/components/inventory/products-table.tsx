// Client-side wrapper around DataTable for the Products list.
//
//   - search filters in-memory (will move to server-side via
//     list_shop_items(p_query) once shops grow real catalogs).
//   - Out-of-stock badge when current_stock <= 0. No low-stock /
//     reorder badge in v1 — reorder thresholds aren't a thing in the
//     v1 East African market.
//   - Cost + price render side-by-side in the same packaging unit
//     (the default sale packaging) so margin is obvious at a glance.
//   - Bulk action: set price only (no bulk-threshold in v1).

"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Search, DollarSign } from "lucide-react";
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
  default_sale_price: number | null;
  default_sale_cost: number | null;
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
          const out = stock <= 0;
          return (
            <div className="flex items-center gap-2 tabular-nums">
              <span
                className={cn("font-medium", out && "text-destructive")}
              >
                {count(stock)} {row.original.base_unit_label}
              </span>
              {out ? (
                <span className="rounded bg-destructive/10 px-1.5 py-0.5 text-xs font-medium text-destructive">
                  {t("outOfStockBadge")}
                </span>
              ) : null}
            </div>
          );
        },
      },
      {
        accessorKey: "default_sale_cost",
        header: t("columns.cost"),
        cell: ({ row }) =>
          row.original.default_sale_cost !== null &&
          row.original.default_sale_cost > 0 ? (
            <span className="tabular-nums text-muted-foreground">
              {money(row.original.default_sale_cost)}
            </span>
          ) : (
            <span className="text-muted-foreground">{t("noPrice")}</span>
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
