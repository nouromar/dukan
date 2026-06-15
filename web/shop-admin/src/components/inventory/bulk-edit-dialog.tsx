// Shared dialog used by both "Set price" and "Set threshold" bulk
// actions. The two flows differ only in label / action callable; one
// dialog with a variant prop keeps the UX consistent and the markup
// in one place.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import {
  bulkSetPriceAction,
  bulkSetThresholdAction,
  type BulkResult,
} from "@/app/(dashboard)/inventory/actions";

export type BulkVariant = "price" | "threshold";

export function BulkEditDialog({
  variant,
  open,
  onOpenChange,
  shopId,
  shopItemIds,
}: {
  variant: BulkVariant;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  shopId: string;
  shopItemIds: string[];
}) {
  const t = useTranslations("inventory.bulk");
  const router = useRouter();
  const [value, setValue] = useState("");
  const [pending, startTransition] = useTransition();

  const isPrice = variant === "price";
  const dialogKey = isPrice ? "priceDialog" : "thresholdDialog";

  function handleConfirm() {
    startTransition(async () => {
      let result: BulkResult;
      if (isPrice) {
        const price = Number(value);
        if (Number.isNaN(price) || price < 0) {
          toast.error(t("errorGeneric"));
          return;
        }
        result = await bulkSetPriceAction({
          shopId,
          shopItemIds,
          price,
        });
      } else {
        // Empty → null (clear the threshold). Otherwise must be a non-negative number.
        const raw = value.trim();
        const threshold = raw === "" ? null : Number(raw);
        if (threshold !== null && (Number.isNaN(threshold) || threshold < 0)) {
          toast.error(t("errorGeneric"));
          return;
        }
        result = await bulkSetThresholdAction({
          shopId,
          shopItemIds,
          threshold,
        });
      }

      if (result.ok) {
        toast.success(
          t(
            isPrice
              ? "successPrice"
              : ("successThreshold" as const),
            { count: result.count },
          ),
        );
        onOpenChange(false);
        setValue("");
        router.refresh();
        return;
      }
      const errorKey = result.code === "permission" ? "errorPermission" : "errorGeneric";
      toast.error(t(errorKey as "errorGeneric"));
    });
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {t(`${dialogKey}.title` as "priceDialog.title")}
          </DialogTitle>
          <DialogDescription>
            {t(`${dialogKey}.description` as "priceDialog.description", {
              count: shopItemIds.length,
            })}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <Label htmlFor={`bulk-${variant}`}>
            {t(`${dialogKey}.label` as "priceDialog.label")}
          </Label>
          <Input
            id={`bulk-${variant}`}
            type="number"
            inputMode="decimal"
            step="any"
            min={0}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder={t(`${dialogKey}.placeholder` as "priceDialog.placeholder")}
            autoFocus
          />
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={pending}
          >
            {t("cancel")}
          </Button>
          <Button
            onClick={handleConfirm}
            disabled={pending || (isPrice && value.trim() === "")}
          >
            {pending
              ? t(`${dialogKey}.submitting` as "priceDialog.submitting")
              : t(`${dialogKey}.confirm` as "priceDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
