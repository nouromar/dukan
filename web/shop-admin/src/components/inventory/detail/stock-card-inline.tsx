// Inline-editable stock card. The stock value itself stays read-only
// (it's a posting-RPC-driven projection); only the reorder threshold
// is editable here. Adjustments to the stock value go through the
// existing Adjust Stock dialog (a separate concern from "set a
// threshold").

"use client";

import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { formatCount } from "shared";
import { Card, CardContent } from "@/components/ui/card";
import { InlineEditNumber } from "@/components/shared/inline-edit";
import { useShopContext } from "@/lib/shop-context";
import { cn } from "@/lib/utils";
import { setProductThresholdAction } from "@/app/(dashboard)/inventory/[shopItemId]/actions";

export function StockCardInline({
  shopId,
  shopItemId,
  currentStock,
  baseUnitLabel,
  initialThreshold,
  locale,
}: {
  shopId: string;
  shopItemId: string;
  currentStock: number;
  baseUnitLabel: string;
  initialThreshold: number | null;
  locale: string;
}) {
  const t = useTranslations("productDetail");
  const { capabilities } = useShopContext();
  const canEdit = capabilities.has("inventory.product.edit");

  const out = currentStock <= 0;
  const low =
    !out && initialThreshold !== null && currentStock <= initialThreshold;

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <Card>
        <CardContent className="pt-6">
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {t("stock.label")}
          </div>
          <div className="mt-1 flex items-baseline gap-3">
            <span
              className={cn(
                "text-3xl font-semibold tabular-nums",
                out && "text-destructive",
                low && "text-amber-600 dark:text-amber-500",
              )}
            >
              {formatCount(currentStock, locale)} {baseUnitLabel}
            </span>
            {out ? (
              <span className="rounded bg-destructive/10 px-2 py-0.5 text-xs font-medium text-destructive">
                {t("stock.outBadge")}
              </span>
            ) : low ? (
              <span className="rounded bg-amber-500/10 px-2 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400">
                {t("stock.lowBadge", {
                  threshold: formatCount(initialThreshold ?? 0, locale),
                  unit: baseUnitLabel,
                })}
              </span>
            ) : null}
          </div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="pt-6">
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {t("editDialog.thresholdLabel")}
          </div>
          <div className="mt-1 flex items-baseline gap-2 text-3xl font-semibold tabular-nums">
            <InlineEditNumber
              value={initialThreshold}
              display={
                initialThreshold === null
                  ? "—"
                  : `${formatCount(initialThreshold, locale)} ${baseUnitLabel}`
              }
              placeholder="0"
              readOnly={!canEdit}
              className="text-3xl font-semibold"
              onSave={async (next) => {
                const r = await setProductThresholdAction({
                  shopId,
                  shopItemId,
                  threshold: next,
                });
                if (!r.ok) {
                  toast.error(
                    r.code === "permission"
                      ? t("editDialog.errorPermission")
                      : t("editDialog.errorGeneric"),
                  );
                  return { ok: false };
                }
                return { ok: true };
              }}
            />
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            {t("editDialog.thresholdHelp")}
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
