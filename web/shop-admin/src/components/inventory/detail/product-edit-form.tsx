// Page-level edit-mode controller for the product detail page.
//
// Replaces the per-field inline-edit pattern (which was invisible on
// touch — no hover affordance). One Edit button toggles the whole
// page between view and edit modes:
//
//   * View mode: clean read-only display. Header (name + category +
//     status chips), stock + threshold cards, packaging table with
//     read-only prices.
//   * Edit mode: a single form Card with labeled inputs for the
//     header fields + threshold, and the packaging price column
//     swaps to editable number inputs. Add/Remove packaging are
//     hidden in edit mode to avoid losing in-flight changes.
//
// Save fires the RPCs only for fields whose values changed since
// entering edit mode (parallel). On success the form exits to view
// mode; on any failure the form stays open so the user can retry
// the failed parts.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations, useLocale } from "next-intl";
import { toast } from "sonner";
import { Pencil, X, Loader2 } from "lucide-react";
import { formatCount } from "shared";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useShopContext } from "@/lib/shop-context";
import { cn } from "@/lib/utils";
import {
  setProductNameAction,
  setProductCategoryAction,
  setProductActiveAction,
  setProductThresholdAction,
  setUnitPriceAction,
} from "@/app/(dashboard)/inventory/[shopItemId]/actions";
import { PackagingTable, type PackagingUnit } from "./packaging-table";
import { AddPackagingDialog, type PackagingUnitOption } from "./add-packaging-dialog";
import { AdjustStockDialog, type AdjustmentReason } from "./adjust-stock-dialog";

export type CategoryOption = { id: string; name: string };

type Mode = "view" | "edit";

type DraftState = {
  name: string;
  categoryId: string;
  isActive: boolean;
  threshold: string;
  prices: Record<string, string>;
};

export function ProductEditForm({
  shopId,
  shopItemId,
  initialName,
  initialCategoryId,
  initialCategoryName,
  initialIsActive,
  initialThreshold,
  currentStock,
  baseUnitLabel,
  categories,
  packagingRows,
  unitOptions,
  adjustmentReasons,
  currencyCode,
}: {
  shopId: string;
  shopItemId: string;
  initialName: string;
  initialCategoryId: string | null;
  initialCategoryName: string | null;
  initialIsActive: boolean;
  initialThreshold: number | null;
  currentStock: number;
  baseUnitLabel: string;
  categories: CategoryOption[];
  packagingRows: PackagingUnit[];
  unitOptions: PackagingUnitOption[];
  adjustmentReasons: AdjustmentReason[];
  currencyCode: string;
}) {
  const t = useTranslations("productDetail");
  const tForm = useTranslations("productDetail.editForm");
  const locale = useLocale();
  const { capabilities } = useShopContext();
  const canEdit = capabilities.has("inventory.product.edit");
  const canAdjust = capabilities.has("inventory.adjustment.post");

  const initial = buildInitial({
    initialName,
    initialCategoryId,
    initialIsActive,
    initialThreshold,
    packagingRows,
  });

  const [mode, setMode] = useState<Mode>("view");
  const [draft, setDraft] = useState<DraftState>(initial);
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  function enterEdit() {
    setDraft(initial);
    setMode("edit");
  }

  function cancel() {
    setDraft(initial);
    setMode("view");
  }

  function handleSave() {
    const ops: Array<{ label: string; run: () => Promise<{ ok: boolean }> }> = [];

    if (draft.name.trim() && draft.name.trim() !== initial.name) {
      ops.push({
        label: tForm("fieldName"),
        run: () =>
          setProductNameAction({
            shopId,
            shopItemId,
            newName: draft.name.trim(),
            languageCode: locale,
          }),
      });
    }
    if (draft.categoryId !== initial.categoryId) {
      ops.push({
        label: tForm("fieldCategory"),
        run: () =>
          setProductCategoryAction({
            shopId,
            shopItemId,
            categoryId: draft.categoryId === "" ? null : draft.categoryId,
          }),
      });
    }
    if (draft.isActive !== initial.isActive) {
      ops.push({
        label: tForm("fieldStatus"),
        run: () =>
          setProductActiveAction({
            shopId,
            shopItemId,
            isActive: draft.isActive,
          }),
      });
    }
    if (draft.threshold !== initial.threshold) {
      const raw = draft.threshold.trim();
      const next = raw === "" ? null : Number(raw);
      ops.push({
        label: tForm("fieldThreshold"),
        run: () =>
          setProductThresholdAction({
            shopId,
            shopItemId,
            threshold: next,
          }),
      });
    }
    for (const row of packagingRows) {
      const id = row.shop_item_unit_id;
      const before = initial.prices[id] ?? "";
      const after = (draft.prices[id] ?? "").trim();
      if (after !== before) {
        const next = after === "" ? null : Number(after);
        ops.push({
          label: `${tForm("fieldPrice")} (${row.unit_label})`,
          run: () =>
            setUnitPriceAction({
              shopId,
              shopItemId,
              shopItemUnitId: id,
              price: next,
            }),
        });
      }
    }

    if (ops.length === 0) {
      toast.message(tForm("noChanges"));
      setMode("view");
      return;
    }

    startTransition(async () => {
      const results = await Promise.all(
        ops.map(async (op) => ({ label: op.label, result: await op.run() })),
      );
      const failed = results.filter((r) => !r.result.ok);
      if (failed.length === 0) {
        toast.success(tForm("savedAll"));
        setMode("view");
        router.refresh();
        return;
      }
      const succeeded = results.length - failed.length;
      toast.error(
        tForm("savedPartial", {
          ok: succeeded,
          failed: failed.length,
          first: failed[0]!.label,
        }),
      );
      // Refresh so any partial successes are reflected on next entry.
      router.refresh();
    });
  }

  return (
    <div className="space-y-6">
      <Toolbar
        mode={mode}
        pending={pending}
        canEdit={canEdit}
        onEdit={enterEdit}
        onCancel={cancel}
        onSave={handleSave}
        adjustStock={
          mode === "view" && canAdjust ? (
            <AdjustStockDialog
              shopId={shopId}
              shopItemId={shopItemId}
              currentStockDisplay={`${formatCount(currentStock, locale)} ${baseUnitLabel}`}
              unitLabel={baseUnitLabel}
              reasons={adjustmentReasons}
            />
          ) : null
        }
      />

      {mode === "view" ? (
        <ViewHeader
          name={initialName}
          categoryName={initialCategoryName}
          isActive={initialIsActive}
        />
      ) : (
        <EditFieldsCard
          draft={draft}
          setDraft={setDraft}
          baseUnitLabel={baseUnitLabel}
          categories={categories}
          pending={pending}
        />
      )}

      <StockSummary
        currentStock={currentStock}
        threshold={initialThreshold}
        baseUnitLabel={baseUnitLabel}
        locale={locale}
        compact={mode === "edit"}
      />

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-sm font-medium">
            {t("sections.packaging")}
          </CardTitle>
          {mode === "view" && canEdit ? (
            <AddPackagingDialog
              shopId={shopId}
              shopItemId={shopItemId}
              baseUnitLabel={baseUnitLabel}
              units={unitOptions}
            />
          ) : null}
        </CardHeader>
        <CardContent>
          <PackagingTable
            shopId={shopId}
            shopItemId={shopItemId}
            rows={packagingRows}
            currencyCode={currencyCode}
            locale={locale}
            emptyMessage={t("packaging.empty")}
            editMode={mode === "edit"}
            priceValues={draft.prices}
            onPriceChange={(id, value) =>
              setDraft((d) => ({
                ...d,
                prices: { ...d.prices, [id]: value },
              }))
            }
          />
        </CardContent>
      </Card>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Toolbar — view: [Adjust][Edit]   edit: [Cancel][Save]
// ----------------------------------------------------------------------------

function Toolbar({
  mode,
  pending,
  canEdit,
  onEdit,
  onCancel,
  onSave,
  adjustStock,
}: {
  mode: Mode;
  pending: boolean;
  canEdit: boolean;
  onEdit: () => void;
  onCancel: () => void;
  onSave: () => void;
  adjustStock: React.ReactNode;
}) {
  const tForm = useTranslations("productDetail.editForm");
  const t = useTranslations("productDetail");

  if (mode === "view") {
    return (
      <div className="flex flex-wrap items-center justify-end gap-2">
        {adjustStock}
        {canEdit ? (
          <Button type="button" variant="default" onClick={onEdit}>
            <Pencil className="mr-1.5 size-4" aria-hidden />
            {t("edit")}
          </Button>
        ) : null}
      </div>
    );
  }

  return (
    <div className="sticky top-0 z-10 -mx-1 flex flex-wrap items-center justify-between gap-2 rounded-md border bg-background/95 px-3 py-2 backdrop-blur supports-[backdrop-filter]:bg-background/70">
      <span className="text-sm font-medium text-foreground">
        {tForm("editingBanner")}
      </span>
      <div className="flex items-center gap-2">
        <Button
          type="button"
          variant="ghost"
          onClick={onCancel}
          disabled={pending}
        >
          <X className="mr-1.5 size-4" aria-hidden />
          {tForm("cancel")}
        </Button>
        <Button type="button" onClick={onSave} disabled={pending}>
          {pending ? (
            <Loader2 className="mr-1.5 size-4 animate-spin" aria-hidden />
          ) : null}
          {pending ? tForm("saving") : tForm("save")}
        </Button>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// View mode header — chips + h1
// ----------------------------------------------------------------------------

function ViewHeader({
  name,
  categoryName,
  isActive,
}: {
  name: string;
  categoryName: string | null;
  isActive: boolean;
}) {
  const t = useTranslations("productDetail");
  return (
    <header className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="rounded-md bg-muted px-2 py-1 text-xs font-medium text-muted-foreground">
          {categoryName ?? t("editForm.categoryNone")}
        </span>
        <span
          className={cn(
            "rounded-md px-2 py-1 text-xs font-medium",
            isActive
              ? "bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"
              : "bg-muted text-muted-foreground",
          )}
        >
          {isActive ? t("editForm.statusActive") : t("editForm.statusHidden")}
        </span>
      </div>
      <h1
        className={cn(
          "text-3xl font-semibold tracking-tight",
          !isActive && "text-muted-foreground line-through",
        )}
      >
        {name}
      </h1>
    </header>
  );
}

// ----------------------------------------------------------------------------
// Edit mode fields card — labeled inputs for the header fields + threshold
// ----------------------------------------------------------------------------

function EditFieldsCard({
  draft,
  setDraft,
  baseUnitLabel,
  categories,
  pending,
}: {
  draft: DraftState;
  setDraft: React.Dispatch<React.SetStateAction<DraftState>>;
  baseUnitLabel: string;
  categories: CategoryOption[];
  pending: boolean;
}) {
  const t = useTranslations("productDetail.editForm");
  return (
    <Card className="border-primary/30">
      <CardContent className="space-y-5 pt-6">
        <div className="space-y-1.5">
          <Label htmlFor="pf-name">{t("fieldName")}</Label>
          <Input
            id="pf-name"
            value={draft.name}
            disabled={pending}
            onChange={(e) =>
              setDraft((d) => ({ ...d, name: e.target.value }))
            }
            maxLength={200}
            autoFocus
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="pf-category">{t("fieldCategory")}</Label>
          <select
            id="pf-category"
            value={draft.categoryId}
            disabled={pending}
            onChange={(e) =>
              setDraft((d) => ({ ...d, categoryId: e.target.value }))
            }
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm shadow-sm"
          >
            <option value="">{t("categoryNone")}</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1.5">
          <Label>{t("fieldStatus")}</Label>
          <div className="flex flex-wrap gap-2">
            <StatusRadio
              value={true}
              current={draft.isActive}
              onChange={(v) => setDraft((d) => ({ ...d, isActive: v }))}
              disabled={pending}
              label={t("statusActive")}
              help={t("statusActiveHelp")}
            />
            <StatusRadio
              value={false}
              current={draft.isActive}
              onChange={(v) => setDraft((d) => ({ ...d, isActive: v }))}
              disabled={pending}
              label={t("statusHidden")}
              help={t("statusHiddenHelp")}
            />
          </div>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="pf-threshold">{t("fieldThreshold")}</Label>
          <div className="flex items-center gap-2">
            <Input
              id="pf-threshold"
              type="number"
              inputMode="decimal"
              step="any"
              min={0}
              value={draft.threshold}
              disabled={pending}
              onChange={(e) =>
                setDraft((d) => ({ ...d, threshold: e.target.value }))
              }
              placeholder="0"
              className="max-w-[10rem]"
            />
            <span className="text-sm text-muted-foreground">
              {baseUnitLabel}
            </span>
          </div>
          <p className="text-xs text-muted-foreground">
            {t("fieldThresholdHelp")}
          </p>
        </div>
      </CardContent>
    </Card>
  );
}

function StatusRadio({
  value,
  current,
  onChange,
  disabled,
  label,
  help,
}: {
  value: boolean;
  current: boolean;
  onChange: (v: boolean) => void;
  disabled: boolean;
  label: string;
  help: string;
}) {
  const selected = current === value;
  return (
    <button
      type="button"
      onClick={() => onChange(value)}
      disabled={disabled}
      className={cn(
        "flex-1 min-w-[10rem] rounded-md border p-3 text-left text-sm transition-colors",
        selected
          ? "border-primary bg-primary/5"
          : "border-border bg-background hover:bg-muted/40",
        disabled && "opacity-60",
      )}
      aria-pressed={selected}
    >
      <div className="flex items-center gap-2 font-medium">
        <span
          className={cn(
            "size-3 rounded-full border-2",
            selected ? "border-primary bg-primary" : "border-muted-foreground/40",
          )}
        />
        {label}
      </div>
      <p className="ml-5 mt-0.5 text-xs text-muted-foreground">{help}</p>
    </button>
  );
}

// ----------------------------------------------------------------------------
// Stock summary — current + threshold side-by-side
// ----------------------------------------------------------------------------

function StockSummary({
  currentStock,
  threshold,
  baseUnitLabel,
  locale,
  compact,
}: {
  currentStock: number;
  threshold: number | null;
  baseUnitLabel: string;
  locale: string;
  compact: boolean;
}) {
  const t = useTranslations("productDetail");
  const out = currentStock <= 0;
  const low = !out && threshold !== null && currentStock <= threshold;

  if (compact) {
    return (
      <Card>
        <CardContent className="pt-6">
          <div className="flex items-baseline justify-between gap-3">
            <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("stock.label")}
            </span>
            <span
              className={cn(
                "text-2xl font-semibold tabular-nums",
                out && "text-destructive",
                low && "text-amber-600 dark:text-amber-500",
              )}
            >
              {formatCount(currentStock, locale)} {baseUnitLabel}
            </span>
          </div>
        </CardContent>
      </Card>
    );
  }

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
                  threshold: formatCount(threshold ?? 0, locale),
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
            {t("editForm.fieldThreshold")}
          </div>
          <div className="mt-1 text-3xl font-semibold tabular-nums">
            {threshold === null
              ? "—"
              : `${formatCount(threshold, locale)} ${baseUnitLabel}`}
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            {t("editForm.fieldThresholdHelp")}
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

// ----------------------------------------------------------------------------
// helpers
// ----------------------------------------------------------------------------

function buildInitial({
  initialName,
  initialCategoryId,
  initialIsActive,
  initialThreshold,
  packagingRows,
}: {
  initialName: string;
  initialCategoryId: string | null;
  initialIsActive: boolean;
  initialThreshold: number | null;
  packagingRows: PackagingUnit[];
}): DraftState {
  const prices: Record<string, string> = {};
  for (const row of packagingRows) {
    prices[row.shop_item_unit_id] =
      row.sale_price === null ? "" : row.sale_price.toString();
  }
  return {
    name: initialName,
    categoryId: initialCategoryId ?? "",
    isActive: initialIsActive,
    threshold:
      initialThreshold === null ? "" : initialThreshold.toString(),
    prices,
  };
}

