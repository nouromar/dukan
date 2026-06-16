// Adds a new shop_item_unit to an existing shop_item. Unit + conversion +
// optional sale price. Uses the existing create_shop_item_unit RPC.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { Plus } from "lucide-react";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { addPackagingAction } from "@/app/(dashboard)/inventory/[shopItemId]/actions";

export type PackagingUnitOption = { code: string; label: string };

export function AddPackagingDialog({
  shopId,
  shopItemId,
  baseUnitLabel,
  units,
}: {
  shopId: string;
  shopItemId: string;
  baseUnitLabel: string;
  units: PackagingUnitOption[];
}) {
  const t = useTranslations("productDetail.packaging.addDialog");
  const tButton = useTranslations("productDetail.packaging");
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [unit, setUnit] = useState(units[0]?.code ?? "");
  const [conversion, setConversion] = useState("");
  const [salePrice, setSalePrice] = useState("");
  const [pending, startTransition] = useTransition();

  function reset() {
    setUnit(units[0]?.code ?? "");
    setConversion("");
    setSalePrice("");
  }

  function handleConfirm() {
    startTransition(async () => {
      const conv = Number(conversion);
      const price = salePrice.trim() === "" ? null : Number(salePrice);
      const result = await addPackagingAction({
        shopId,
        shopItemId,
        unitCode: unit,
        conversionToBase: conv,
        salePrice: price,
      });
      if (result.ok) {
        toast.success(t("success"));
        setOpen(false);
        reset();
        router.refresh();
        return;
      }
      const key = (
        {
          validation: "errorValidation",
          permission: "errorPermission",
          duplicate: "errorDuplicate",
          generic: "errorGeneric",
        } as const
      )[result.code];
      toast.error(t(key as "errorGeneric"));
    });
  }

  const conv = Number(conversion);
  const canSubmit =
    !pending &&
    unit !== "" &&
    conversion.trim() !== "" &&
    !Number.isNaN(conv) &&
    conv > 0;

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
        <Plus className="size-4" aria-hidden />
        {tButton("addButton")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("title")}</DialogTitle>
          <DialogDescription>{t("description")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Label htmlFor="pkg-unit" className="shrink-0 w-32">
              {t("unitLabel")}
            </Label>
            <select
              id="pkg-unit"
              value={unit}
              onChange={(e) => setUnit(e.target.value)}
              className="flex h-9 flex-1 rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              {units.map((u) => (
                <option key={u.code} value={u.code}>
                  {u.label} ({u.code})
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="pkg-conv">
              {t("conversionLabel")} ({baseUnitLabel})
            </Label>
            <Input
              id="pkg-conv"
              type="number"
              inputMode="decimal"
              step="any"
              min={0}
              value={conversion}
              onChange={(e) => setConversion(e.target.value)}
              placeholder="25"
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              {t("conversionHelp")}
            </p>
          </div>
          <div className="space-y-2">
            <Label htmlFor="pkg-price">{t("salePriceLabel")}</Label>
            <Input
              id="pkg-price"
              type="number"
              inputMode="decimal"
              step="any"
              min={0}
              value={salePrice}
              onChange={(e) => setSalePrice(e.target.value)}
              placeholder="0.00"
            />
            <p className="text-xs text-muted-foreground">
              {t("salePriceHelp")}
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => setOpen(false)}
            disabled={pending}
          >
            {t("cancel")}
          </Button>
          <Button onClick={handleConfirm} disabled={!canSubmit}>
            {pending ? t("submitting") : t("confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
