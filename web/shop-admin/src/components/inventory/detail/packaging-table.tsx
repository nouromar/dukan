// Packaging breakdown table. One row per shop_item_unit returned by
// get_shop_item.units. Two modes:
//
//   * View mode (default): sale prices render as plain read-only money.
//     Each non-base packaging gets a Remove action in the last column.
//   * Edit mode: sale prices become controlled number inputs driven by
//     the parent ProductEditForm. Remove action is hidden — structural
//     changes shouldn't compete with field edits in flight.

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
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { useShopContext } from "@/lib/shop-context";
import { RemovePackagingButton } from "./remove-packaging-button";

export type PackagingUnit = {
  shop_item_unit_id: string;
  unit_code: string;
  unit_label: string;
  packaging_label: string;
  conversion_to_base: number;
  sale_price: number | null;
  last_cost: number | null;
  is_default_sale: boolean;
  is_default_receive: boolean;
  is_base_unit: boolean;
  is_active: boolean;
  sort_order: number;
};

export function PackagingTable({
  shopId,
  shopItemId,
  rows,
  currencyCode,
  locale,
  emptyMessage,
  editMode = false,
  priceValues,
  onPriceChange,
}: {
  shopId: string;
  shopItemId: string;
  rows: PackagingUnit[];
  currencyCode: string;
  locale: string;
  emptyMessage: string;
  editMode?: boolean;
  priceValues?: Record<string, string>;
  onPriceChange?: (shopItemUnitId: string, value: string) => void;
}) {
  const t = useTranslations("productDetail.packaging");
  const tProd = useTranslations("productDetail");
  const { capabilities } = useShopContext();
  const canEdit = capabilities.has("inventory.product.edit");
  const showActions = canEdit && !editMode;
  const money = (n: number) => formatMoney(n, currencyCode, locale);

  const sorted = useMemo(
    () =>
      [...rows].sort(
        (a, b) =>
          a.sort_order - b.sort_order ||
          a.conversion_to_base - b.conversion_to_base,
      ),
    [rows],
  );

  if (sorted.length === 0) {
    return <p className="py-4 text-sm text-muted-foreground">{emptyMessage}</p>;
  }

  return (
    <div className="overflow-hidden rounded-lg border">
      <Table>
        <TableHeader className="bg-muted/30">
          <TableRow>
            <TableHead className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.name")}
            </TableHead>
            <TableHead className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.conversion")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.salePrice")}
            </TableHead>
            <TableHead className="text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.lastCost")}
            </TableHead>
            <TableHead className="text-center text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.defaultSale")}
            </TableHead>
            <TableHead className="text-center text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("columns.defaultReceive")}
            </TableHead>
            {showActions ? (
              <TableHead className="w-24 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">
                {t("columns.actions")}
              </TableHead>
            ) : null}
          </TableRow>
        </TableHeader>
        <TableBody>
          {sorted.map((u) => (
            <TableRow
              key={u.shop_item_unit_id}
              className={cn(!u.is_active && "text-muted-foreground opacity-60")}
            >
              <TableCell
                className={cn(
                  "font-medium",
                  !u.is_active && "line-through",
                )}
              >
                {u.unit_label}
              </TableCell>
              <TableCell className="text-sm text-muted-foreground">
                {u.packaging_label}
              </TableCell>
              <TableCell className="text-right">
                {editMode && u.is_active ? (
                  <Input
                    type="number"
                    inputMode="decimal"
                    step="any"
                    min={0}
                    value={priceValues?.[u.shop_item_unit_id] ?? ""}
                    onChange={(e) =>
                      onPriceChange?.(u.shop_item_unit_id, e.target.value)
                    }
                    className="ml-auto h-8 max-w-[8rem] text-right tabular-nums"
                    placeholder="—"
                  />
                ) : u.sale_price === null ? (
                  <span className="text-muted-foreground tabular-nums">
                    {tProd("noPrice")}
                  </span>
                ) : (
                  <span className="font-medium tabular-nums">
                    {money(u.sale_price)}
                  </span>
                )}
              </TableCell>
              <TableCell className="text-right tabular-nums">
                {u.last_cost !== null ? (
                  <span className="text-sm text-muted-foreground">
                    {money(u.last_cost)}
                  </span>
                ) : (
                  <span className="text-muted-foreground">
                    {tProd("noPrice")}
                  </span>
                )}
              </TableCell>
              <TableCell className="text-center text-primary">
                {u.is_default_sale ? t("defaultYes") : ""}
              </TableCell>
              <TableCell className="text-center text-primary">
                {u.is_default_receive ? t("defaultYes") : ""}
              </TableCell>
              {showActions ? (
                <TableCell className="text-right">
                  {!u.is_base_unit && u.is_active ? (
                    <RemovePackagingButton
                      shopId={shopId}
                      shopItemId={shopItemId}
                      shopItemUnitId={u.shop_item_unit_id}
                    />
                  ) : null}
                </TableCell>
              ) : null}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
