// Record-receive form. One page, multi-line entry, no wizard. Header
// fields are a Card; lines render as a table with an Add-line button.
// Cost-entry mode is global (per receive) — the bono is usually all
// one form or all the other, switching per-line would be friction.
//
// Save calls post_receive via the Server Action and on success
// redirects to /receives/[txn_id]. On any failure the form stays
// open with a toast so the owner can fix and retry without losing
// in-flight lines.

"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { Plus, Trash2, Loader2 } from "lucide-react";
import { formatMoney } from "shared";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import {
  postReceiveAction,
  type ReceiveLineInput,
} from "@/app/(dashboard)/receives/new/actions";

export type SupplierOption = { id: string; name: string };
export type ProductOption = { id: string; displayName: string };
export type PackagingOption = {
  shopItemUnitId: string;
  shopItemId: string;
  unitCode: string;
  unitLabel: string;
  packagingLabel: string;
  conversionToBase: number;
  isDefaultReceive: boolean;
  lastCost: number | null;
};

type Line = {
  id: string;
  shopItemId: string;
  shopItemUnitId: string;
  quantity: string;
  cost: string;
};

let lineIdSeed = 1;
function nextLineId() {
  lineIdSeed += 1;
  return `l${lineIdSeed}`;
}

export function RecordReceiveForm({
  shopId,
  suppliers,
  products,
  packagings,
  currencyCode,
  locale,
  todayIso,
}: {
  shopId: string;
  suppliers: SupplierOption[];
  products: ProductOption[];
  packagings: PackagingOption[];
  currencyCode: string;
  locale: string;
  /** Server-rendered "today" in YYYY-MM-DD; passed in to avoid Date.now() in the bundle. */
  todayIso: string;
}) {
  const t = useTranslations("recordReceive");
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  const [partyId, setPartyId] = useState("");
  const [occurredDate, setOccurredDate] = useState(todayIso);
  const [paymentMethod, setPaymentMethod] = useState<"cash" | "credit">(
    "credit",
  );
  const [costMode, setCostMode] = useState<"unit" | "lineTotal">("unit");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<Line[]>([
    {
      id: nextLineId(),
      shopItemId: "",
      shopItemUnitId: "",
      quantity: "",
      cost: "",
    },
  ]);

  const money = (n: number) => formatMoney(n, currencyCode, locale);

  const packagingsByItem = useMemo(() => {
    const map = new Map<string, PackagingOption[]>();
    for (const p of packagings) {
      const list = map.get(p.shopItemId) ?? [];
      list.push(p);
      map.set(p.shopItemId, list);
    }
    return map;
  }, [packagings]);

  function setLine(id: string, patch: Partial<Line>) {
    setLines((prev) =>
      prev.map((l) => (l.id === id ? { ...l, ...patch } : l)),
    );
  }

  function pickProductForLine(lineId: string, shopItemId: string) {
    const options = packagingsByItem.get(shopItemId) ?? [];
    const def =
      options.find((o) => o.isDefaultReceive) ??
      options.find((o) => o.conversionToBase === 1) ??
      options[0];
    setLine(lineId, {
      shopItemId,
      shopItemUnitId: def?.shopItemUnitId ?? "",
      // Suggest the last cost as the unit-cost default if we know it
      // and the user hasn't typed anything yet.
      cost:
        costMode === "unit" && def?.lastCost !== null && def?.lastCost !== undefined
          ? String(def.lastCost)
          : "",
    });
  }

  function addLine() {
    setLines((prev) => [
      ...prev,
      {
        id: nextLineId(),
        shopItemId: "",
        shopItemUnitId: "",
        quantity: "",
        cost: "",
      },
    ]);
  }

  function removeLine(id: string) {
    setLines((prev) =>
      prev.length <= 1 ? prev : prev.filter((l) => l.id !== id),
    );
  }

  function lineSubtotal(line: Line): number {
    const qty = Number(line.quantity);
    const cost = Number(line.cost);
    if (!Number.isFinite(qty) || !Number.isFinite(cost)) return 0;
    if (costMode === "unit") return qty * cost;
    return cost;
  }

  const grandTotal = lines.reduce((sum, l) => sum + lineSubtotal(l), 0);

  function canSubmit(): boolean {
    if (!partyId || !occurredDate) return false;
    if (lines.length === 0) return false;
    return lines.every((l) => {
      const qty = Number(l.quantity);
      const cost = Number(l.cost);
      return (
        l.shopItemUnitId !== "" &&
        Number.isFinite(qty) &&
        qty > 0 &&
        Number.isFinite(cost) &&
        cost >= 0
      );
    });
  }

  function handleSave() {
    if (!canSubmit()) {
      toast.error(t("errorIncomplete"));
      return;
    }
    const payload: ReceiveLineInput[] = lines.map((l) => {
      const qty = Number(l.quantity);
      const cost = Number(l.cost);
      return costMode === "unit"
        ? { shopItemUnitId: l.shopItemUnitId, quantity: qty, unitCost: cost }
        : {
            shopItemUnitId: l.shopItemUnitId,
            quantity: qty,
            lineTotal: cost,
          };
    });
    startTransition(async () => {
      const r = await postReceiveAction({
        shopId,
        partyId,
        occurredAt: occurredDate,
        paymentMethod,
        lines: payload,
        notes: notes.trim() === "" ? null : notes.trim(),
      });
      if (r.ok) {
        toast.success(t("success"));
        router.push(`/receives/${r.txnId}`);
        return;
      }
      const key = (
        {
          validation: "errorValidation",
          permission: "errorPermission",
          supplier: "errorSupplier",
          generic: "errorGeneric",
        } as const
      )[r.code];
      toast.error(t(key as "errorGeneric"));
    });
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <Card>
        <CardContent className="grid grid-cols-1 gap-4 pt-6 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="rr-supplier">{t("supplierLabel")}</Label>
            <select
              id="rr-supplier"
              value={partyId}
              onChange={(e) => setPartyId(e.target.value)}
              disabled={pending}
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              <option value="">{t("supplierPlaceholder")}</option>
              {suppliers.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="rr-date">{t("dateLabel")}</Label>
            <Input
              id="rr-date"
              type="date"
              value={occurredDate}
              max={todayIso}
              onChange={(e) => setOccurredDate(e.target.value)}
              disabled={pending}
            />
          </div>
          <div className="space-y-1.5">
            <Label>{t("paymentLabel")}</Label>
            <div className="flex gap-2">
              <ChoiceButton
                selected={paymentMethod === "credit"}
                onClick={() => setPaymentMethod("credit")}
                disabled={pending}
              >
                {t("paymentCredit")}
              </ChoiceButton>
              <ChoiceButton
                selected={paymentMethod === "cash"}
                onClick={() => setPaymentMethod("cash")}
                disabled={pending}
              >
                {t("paymentCash")}
              </ChoiceButton>
            </div>
            <p className="text-xs text-muted-foreground">
              {paymentMethod === "credit"
                ? t("paymentCreditHelp")
                : t("paymentCashHelp")}
            </p>
          </div>
          <div className="space-y-1.5">
            <Label>{t("costModeLabel")}</Label>
            <div className="flex gap-2">
              <ChoiceButton
                selected={costMode === "unit"}
                onClick={() => setCostMode("unit")}
                disabled={pending}
              >
                {t("costModeUnit")}
              </ChoiceButton>
              <ChoiceButton
                selected={costMode === "lineTotal"}
                onClick={() => setCostMode("lineTotal")}
                disabled={pending}
              >
                {t("costModeLineTotal")}
              </ChoiceButton>
            </div>
            <p className="text-xs text-muted-foreground">
              {costMode === "unit"
                ? t("costModeUnitHelp")
                : t("costModeLineTotalHelp")}
            </p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-sm font-medium">
            {t("linesTitle")}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="overflow-hidden rounded-lg border">
            <table className="w-full text-sm">
              <thead className="bg-muted/30 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-3 py-2 text-left">{t("lineColumns.product")}</th>
                  <th className="px-3 py-2 text-left">{t("lineColumns.packaging")}</th>
                  <th className="px-3 py-2 text-right">{t("lineColumns.quantity")}</th>
                  <th className="px-3 py-2 text-right">
                    {costMode === "unit"
                      ? t("lineColumns.unitCost")
                      : t("lineColumns.lineTotalCost")}
                  </th>
                  <th className="px-3 py-2 text-right">
                    {t("lineColumns.subtotal")}
                  </th>
                  <th className="w-12 px-3 py-2" aria-label="remove" />
                </tr>
              </thead>
              <tbody>
                {lines.map((line) => {
                  const packagingOptions =
                    packagingsByItem.get(line.shopItemId) ?? [];
                  return (
                    <tr key={line.id} className="border-t">
                      <td className="px-3 py-2">
                        <select
                          value={line.shopItemId}
                          onChange={(e) =>
                            pickProductForLine(line.id, e.target.value)
                          }
                          disabled={pending}
                          className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm"
                        >
                          <option value="">{t("productPlaceholder")}</option>
                          {products.map((p) => (
                            <option key={p.id} value={p.id}>
                              {p.displayName}
                            </option>
                          ))}
                        </select>
                      </td>
                      <td className="px-3 py-2">
                        <select
                          value={line.shopItemUnitId}
                          onChange={(e) =>
                            setLine(line.id, {
                              shopItemUnitId: e.target.value,
                            })
                          }
                          disabled={pending || !line.shopItemId}
                          className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm"
                        >
                          {!line.shopItemId ? (
                            <option value="">—</option>
                          ) : null}
                          {packagingOptions.map((p) => (
                            <option
                              key={p.shopItemUnitId}
                              value={p.shopItemUnitId}
                            >
                              {p.packagingLabel}
                            </option>
                          ))}
                        </select>
                      </td>
                      <td className="px-3 py-2">
                        <Input
                          type="number"
                          inputMode="decimal"
                          step="any"
                          min={0}
                          value={line.quantity}
                          onChange={(e) =>
                            setLine(line.id, { quantity: e.target.value })
                          }
                          disabled={pending}
                          className="h-9 max-w-[7rem] text-right tabular-nums ml-auto"
                          placeholder="0"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <Input
                          type="number"
                          inputMode="decimal"
                          step="any"
                          min={0}
                          value={line.cost}
                          onChange={(e) =>
                            setLine(line.id, { cost: e.target.value })
                          }
                          disabled={pending}
                          className="h-9 max-w-[8rem] text-right tabular-nums ml-auto"
                          placeholder="0"
                        />
                      </td>
                      <td className="px-3 py-2 text-right tabular-nums text-muted-foreground">
                        {money(lineSubtotal(line))}
                      </td>
                      <td className="px-1 py-2 text-right">
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          onClick={() => removeLine(line.id)}
                          disabled={pending || lines.length <= 1}
                          className="h-7 px-2 text-muted-foreground hover:text-destructive"
                          aria-label={t("removeLine")}
                        >
                          <Trash2 className="size-4" aria-hidden />
                        </Button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <div className="flex items-center justify-between">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={addLine}
              disabled={pending}
              className="gap-2"
            >
              <Plus className="size-4" aria-hidden />
              {t("addLine")}
            </Button>
            <div className="text-right">
              <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                {t("grandTotal")}
              </div>
              <div className="text-2xl font-semibold tabular-nums">
                {money(grandTotal)}
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-1.5 pt-6">
          <Label htmlFor="rr-notes">{t("notesLabel")}</Label>
          <Textarea
            id="rr-notes"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder={t("notesPlaceholder")}
            rows={2}
            disabled={pending}
          />
        </CardContent>
      </Card>

      <div className="flex items-center justify-end gap-2">
        <Button
          type="button"
          variant="ghost"
          onClick={() => router.push("/receives")}
          disabled={pending}
        >
          {t("cancel")}
        </Button>
        <Button
          type="button"
          onClick={handleSave}
          disabled={pending || !canSubmit()}
        >
          {pending ? (
            <Loader2 className="mr-1.5 size-4 animate-spin" aria-hidden />
          ) : null}
          {pending ? t("saving") : t("save")}
        </Button>
      </div>
    </div>
  );
}

function ChoiceButton({
  selected,
  onClick,
  disabled,
  children,
}: {
  selected: boolean;
  onClick: () => void;
  disabled: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "flex-1 rounded-md border px-3 py-2 text-sm font-medium transition-colors",
        selected
          ? "border-primary bg-primary/5 text-foreground"
          : "border-border bg-background text-muted-foreground hover:bg-muted/40",
        disabled && "opacity-60",
      )}
      aria-pressed={selected}
    >
      {children}
    </button>
  );
}
