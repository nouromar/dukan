// Add Product dialog launched from /inventory header. Caller passes
// the category + unit lookups so the selects are populated
// server-side (no extra client roundtrip).

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations, useLocale } from "next-intl";
import { toast } from "sonner";
import { Plus } from "lucide-react";
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
import { cn } from "@/lib/utils";
import { addProductAction } from "@/app/(dashboard)/inventory/actions";

export type UnitOption = { code: string; label: string };
export type CategoryOption = { id: string; name: string };

export function AddProductDialog({
  shopId,
  units,
  categories,
}: {
  shopId: string;
  units: UnitOption[];
  categories: CategoryOption[];
}) {
  const t = useTranslations("inventory");
  const locale = useLocale();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [baseUnit, setBaseUnit] = useState(units[0]?.code ?? "");
  const [categoryId, setCategoryId] = useState<string>("");
  const [salePrice, setSalePrice] = useState("");
  const [pending, startTransition] = useTransition();

  function reset() {
    setName("");
    setBaseUnit(units[0]?.code ?? "");
    setCategoryId("");
    setSalePrice("");
  }

  function handleConfirm() {
    startTransition(async () => {
      const price =
        salePrice.trim() === "" ? null : Number(salePrice);
      const result = await addProductAction({
        shopId,
        name,
        baseUnitCode: baseUnit,
        categoryId: categoryId === "" ? null : categoryId,
        salePrice: price,
        languageCode: locale,
      });
      if (result.ok) {
        toast.success(t("addDialog.success", { name: result.name }));
        setOpen(false);
        reset();
        router.refresh();
        return;
      }
      const key = (
        {
          missing_name: "addDialog.errorName",
          missing_base_unit: "addDialog.errorBaseUnit",
          permission: "addDialog.errorPermission",
          duplicate: "addDialog.errorDuplicate",
          generic: "addDialog.errorGeneric",
        } as const
      )[result.code];
      toast.error(t(key as "addDialog.errorGeneric"));
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
      <DialogTrigger className={cn(buttonVariants({ size: "sm" }), "gap-2")}>
        <Plus className="size-4" aria-hidden />
        {t("addButton")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("addDialog.title")}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="product-name">{t("addDialog.nameLabel")}</Label>
            <Input
              id="product-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("addDialog.namePlaceholder")}
              maxLength={200}
              autoFocus
            />
          </div>
          <div className="flex items-center gap-3">
            <Label htmlFor="product-unit" className="shrink-0 w-28">
              {t("addDialog.baseUnitLabel")}
            </Label>
            <select
              id="product-unit"
              value={baseUnit}
              onChange={(e) => setBaseUnit(e.target.value)}
              className="flex h-9 flex-1 rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              {units.map((u) => (
                <option key={u.code} value={u.code}>
                  {u.label} ({u.code})
                </option>
              ))}
            </select>
          </div>
          <div className="flex items-center gap-3">
            <Label htmlFor="product-category" className="shrink-0 w-28">
              {t("addDialog.categoryLabel")}
            </Label>
            <select
              id="product-category"
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              className="flex h-9 flex-1 rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              <option value="">{t("addDialog.categoryNone")}</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="product-price">
              {t("addDialog.salePriceLabel")}
            </Label>
            <Input
              id="product-price"
              type="number"
              inputMode="decimal"
              step="any"
              min={0}
              value={salePrice}
              onChange={(e) => setSalePrice(e.target.value)}
              placeholder="0.00"
            />
            <p className="text-xs text-muted-foreground">
              {t("addDialog.salePriceHelp")}
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => setOpen(false)}
            disabled={pending}
          >
            {t("addDialog.cancel")}
          </Button>
          <Button
            onClick={handleConfirm}
            disabled={
              pending || name.trim().length === 0 || baseUnit.length === 0
            }
          >
            {pending ? t("addDialog.submitting") : t("addDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
