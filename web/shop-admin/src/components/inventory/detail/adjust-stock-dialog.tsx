// Stock adjustment dialog. Owner-only. Single-line wrapper around the
// existing post_inventory_adjustment RPC. Quantity delta + reason
// dropdown + optional notes. Current stock shown for context.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { Sliders } from "lucide-react";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { adjustStockAction } from "@/app/(dashboard)/inventory/[shopItemId]/actions";

export type AdjustmentReason = {
  code: string;
  label: string;
  /** true = increase only; false = decrease only; null = either. */
  is_increase: boolean | null;
};

export function AdjustStockDialog({
  shopId,
  shopItemId,
  currentStockDisplay,
  unitLabel,
  reasons,
}: {
  shopId: string;
  shopItemId: string;
  currentStockDisplay: string;
  unitLabel: string;
  reasons: AdjustmentReason[];
}) {
  const t = useTranslations("productDetail");
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [delta, setDelta] = useState("");
  const [reasonCode, setReasonCode] = useState(reasons[0]?.code ?? "");
  const [notes, setNotes] = useState("");
  const [pending, startTransition] = useTransition();

  function reset() {
    setDelta("");
    setReasonCode(reasons[0]?.code ?? "");
    setNotes("");
  }

  function handleConfirm() {
    startTransition(async () => {
      const value = Number(delta);
      const result = await adjustStockAction({
        shopId,
        shopItemId,
        quantityDelta: value,
        reasonCode,
        notes: notes.trim() === "" ? null : notes.trim(),
      });
      if (result.ok) {
        toast.success(t("adjustDialog.success"));
        setOpen(false);
        reset();
        router.refresh();
        return;
      }
      const key = (
        {
          validation: "adjustDialog.errorEmpty",
          reason_mismatch: "adjustDialog.errorReasonMismatch",
          permission: "adjustDialog.errorPermission",
          generic: "adjustDialog.errorGeneric",
        } as const
      )[result.code];
      toast.error(t(key as "adjustDialog.errorGeneric"));
    });
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (!o) reset();
      }}
    >
      <DialogTrigger
        className={cn(
          buttonVariants({ variant: "outline", size: "sm" }),
          "gap-2",
        )}
      >
        <Sliders className="size-4" aria-hidden />
        {t("adjustStock")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("adjustDialog.title")}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="rounded-md bg-muted/40 p-3">
            <div className="text-xs uppercase tracking-wide text-muted-foreground">
              {t("adjustDialog.currentLabel")}
            </div>
            <div className="text-xl font-semibold tabular-nums">
              {currentStockDisplay}
            </div>
          </div>
          <div className="space-y-2">
            <Label htmlFor="adj-delta">
              {t("adjustDialog.deltaLabel")} ({unitLabel})
            </Label>
            <Input
              id="adj-delta"
              type="number"
              inputMode="decimal"
              step="any"
              value={delta}
              onChange={(e) => setDelta(e.target.value)}
              placeholder="0"
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              {t("adjustDialog.deltaHelp")}
            </p>
          </div>
          <div className="flex items-center gap-3">
            <Label htmlFor="adj-reason" className="shrink-0 w-20">
              {t("adjustDialog.reasonLabel")}
            </Label>
            <select
              id="adj-reason"
              value={reasonCode}
              onChange={(e) => setReasonCode(e.target.value)}
              className="flex h-9 flex-1 rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              {reasons.map((r) => (
                <option key={r.code} value={r.code}>
                  {r.label}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="adj-notes">{t("adjustDialog.notesLabel")}</Label>
            <Textarea
              id="adj-notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder={t("adjustDialog.notesPlaceholder")}
              rows={2}
            />
          </div>
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => setOpen(false)}
            disabled={pending}
          >
            {t("adjustDialog.cancel")}
          </Button>
          <Button
            onClick={handleConfirm}
            disabled={
              pending ||
              delta.trim() === "" ||
              Number(delta) === 0 ||
              reasonCode === ""
            }
          >
            {pending ? t("adjustDialog.submitting") : t("adjustDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
