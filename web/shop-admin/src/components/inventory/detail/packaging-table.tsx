// Packaging breakdown table. One row per shop_item_unit returned by
// get_shop_item.units. Sale-price cell is inline-editable when the
// viewer can edit (capability inventory.product.edit) — auto-saves
// on blur or Enter via setUnitPriceAction.

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
import { cn } from "@/lib/utils";
import { useShopContext } from "@/lib/shop-context";
import { PriceEditCell } from "./price-edit-cell";

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
}: {
  shopId: string;
  shopItemId: string;
  rows: PackagingUnit[];
  currencyCode: string;
  locale: string;
  emptyMessage: string;
}) {
  const t = useTranslations("productDetail.packaging");
  const tProd = useTranslations("productDetail");
  const { capabilities } = useShopContext();
  // Single-row edits use the cashier-or-better cap; align here.
  // (Bulk edits require inventory.product.bulk_edit; this is the
  // looser gate matching the underlying RPC's auth_can_post_shop.)
  const canEdit = capabilities.has("inventory.product.edit");
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
          </TableRow>
        </TableHeader>
        <TableBody>
          {sorted.map((u) => (
            <TableRow
              key={u.shop_item_unit_id}
              className={cn(!u.is_active && "text-muted-foreground")}
            >
              <TableCell className={cn("font-medium", !u.is_active && "line-through")}>
                {u.unit_label}
              </TableCell>
              <TableCell className="text-sm text-muted-foreground">
                {u.packaging_label}
              </TableCell>
              <TableCell className="text-right">
                <PriceEditCell
                  shopId={shopId}
                  shopItemId={shopItemId}
                  shopItemUnitId={u.shop_item_unit_id}
                  initialPrice={u.sale_price}
                  currencyCode={currencyCode}
                  locale={locale}
                  canEdit={canEdit && u.is_active}
                />
              </TableCell>
              <TableCell className="text-right tabular-nums">
                {u.last_cost !== null ? (
                  <span className="text-sm text-muted-foreground">
                    {money(u.last_cost)}
                  </span>
                ) : (
                  <span className="text-muted-foreground">{tProd("noPrice")}</span>
                )}
              </TableCell>
              <TableCell className="text-center text-primary">
                {u.is_default_sale ? t("defaultYes") : ""}
              </TableCell>
              <TableCell className="text-center text-primary">
                {u.is_default_receive ? t("defaultYes") : ""}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
