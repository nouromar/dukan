// "Set price" bulk-edit dialog. The dialog used to multiplex price /
// threshold via a `variant` prop; per #334 v1 doesn't support
// per-item reorder thresholds, so the dialog is now price-only.
// (The threshold branch can be re-added when reorder lands —
// bulkSetThresholdAction needs restoring first.)

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
import { bulkSetPriceAction } from "@/app/(dashboard)/inventory/actions";

export function BulkEditDialog({
  open,
  onOpenChange,
  shopId,
  shopItemIds,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  shopId: string;
  shopItemIds: string[];
}) {
  const t = useTranslations("inventory.bulk");
  const router = useRouter();
  const [value, setValue] = useState("");
  const [pending, startTransition] = useTransition();

  function handleConfirm() {
    startTransition(async () => {
      const price = Number(value);
      if (Number.isNaN(price) || price < 0) {
        toast.error(t("errorGeneric"));
        return;
      }
      const result = await bulkSetPriceAction({
        shopId,
        shopItemIds,
        price,
      });

      if (result.ok) {
        toast.success(t("successPrice", { count: result.count }));
        onOpenChange(false);
        setValue("");
        router.refresh();
        return;
      }
      const errorKey =
        result.code === "permission" ? "errorPermission" : "errorGeneric";
      toast.error(t(errorKey as "errorGeneric"));
    });
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("priceDialog.title")}</DialogTitle>
          <DialogDescription>
            {t("priceDialog.description", { count: shopItemIds.length })}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <Label htmlFor="bulk-price">{t("priceDialog.label")}</Label>
          <Input
            id="bulk-price"
            type="number"
            inputMode="decimal"
            step="any"
            min={0}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder={t("priceDialog.placeholder")}
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
            disabled={pending || value.trim() === ""}
          >
            {pending ? t("priceDialog.submitting") : t("priceDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
