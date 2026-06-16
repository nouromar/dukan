// Edit Product dialog. Multi-field; only changed fields fire RPCs.
// Adding a new display name appends an alias and marks it display
// (the old name stays as a non-display alias). Toggle active hides
// the product from new sales/receives without deleting history.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations, useLocale } from "next-intl";
import { toast } from "sonner";
import { Pencil } from "lucide-react";
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
import { editProductAction } from "@/app/(dashboard)/inventory/[shopItemId]/actions";

export type EditCategoryOption = { id: string; name: string };

export function EditProductDialog({
  shopId,
  shopItemId,
  initialName,
  initialCategoryId,
  initialThreshold,
  initialIsActive,
  categories,
}: {
  shopId: string;
  shopItemId: string;
  initialName: string;
  initialCategoryId: string | null;
  initialThreshold: number | null;
  initialIsActive: boolean;
  categories: EditCategoryOption[];
}) {
  const t = useTranslations("productDetail");
  const locale = useLocale();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(initialName);
  const [categoryId, setCategoryId] = useState<string>(initialCategoryId ?? "");
  const [threshold, setThreshold] = useState<string>(
    initialThreshold === null ? "" : initialThreshold.toString(),
  );
  const [isActive, setIsActive] = useState(initialIsActive);
  const [pending, startTransition] = useTransition();

  function reset() {
    setName(initialName);
    setCategoryId(initialCategoryId ?? "");
    setThreshold(initialThreshold === null ? "" : initialThreshold.toString());
    setIsActive(initialIsActive);
  }

  function handleSave() {
    startTransition(async () => {
      const nameChanged = name.trim() !== initialName.trim();
      const newCategoryId = categoryId === "" ? null : categoryId;
      const categoryChanged = newCategoryId !== initialCategoryId;
      const rawThreshold = threshold.trim();
      const newThreshold = rawThreshold === "" ? null : Number(rawThreshold);
      const thresholdChanged =
        (initialThreshold === null && newThreshold !== null) ||
        (initialThreshold !== null && newThreshold !== initialThreshold);
      const activeChanged = isActive !== initialIsActive;

      if (
        !nameChanged &&
        !categoryChanged &&
        !thresholdChanged &&
        !activeChanged
      ) {
        setOpen(false);
        return;
      }

      const result = await editProductAction({
        shopId,
        shopItemId,
        newName: nameChanged ? name.trim() : null,
        newNameLocale: locale,
        categoryId: categoryChanged ? newCategoryId : undefined,
        threshold: thresholdChanged ? newThreshold : undefined,
        isActive: activeChanged ? isActive : undefined,
      });
      if (result.ok) {
        toast.success(t("editDialog.saved"));
        setOpen(false);
        router.refresh();
        return;
      }
      const key =
        result.code === "permission"
          ? "editDialog.errorPermission"
          : "editDialog.errorGeneric";
      toast.error(t(key as "editDialog.errorGeneric"));
    });
  }

  const dirty =
    name.trim() !== initialName.trim() ||
    (categoryId === "" ? null : categoryId) !== initialCategoryId ||
    (threshold.trim() === "" ? null : Number(threshold)) !== initialThreshold ||
    isActive !== initialIsActive;

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
        <Pencil className="size-4" aria-hidden />
        {t("edit")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("editDialog.title")}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="edit-name">{t("editDialog.nameLabel")}</Label>
            <Input
              id="edit-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={200}
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              {t("editDialog.nameHelp")}
            </p>
          </div>
          <div className="flex items-center gap-3">
            <Label htmlFor="edit-category" className="shrink-0 w-28">
              {t("editDialog.categoryLabel")}
            </Label>
            <select
              id="edit-category"
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              className="flex h-9 flex-1 rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              <option value="">{t("editDialog.categoryNone")}</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="edit-threshold">
              {t("editDialog.thresholdLabel")}
            </Label>
            <Input
              id="edit-threshold"
              type="number"
              inputMode="decimal"
              step="any"
              min={0}
              value={threshold}
              onChange={(e) => setThreshold(e.target.value)}
              placeholder="0"
            />
            <p className="text-xs text-muted-foreground">
              {t("editDialog.thresholdHelp")}
            </p>
          </div>
          <div className="flex items-start gap-3 rounded-md border p-3">
            <input
              id="edit-active"
              type="checkbox"
              checked={isActive}
              onChange={(e) => setIsActive(e.target.checked)}
              className="mt-1"
            />
            <div className="flex-1">
              <Label htmlFor="edit-active" className="font-medium">
                {t("editDialog.activeLabel")}
              </Label>
              <p className="text-xs text-muted-foreground">
                {isActive ? t("editDialog.activeOn") : t("editDialog.activeOff")}
              </p>
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => setOpen(false)}
            disabled={pending}
          >
            {t("editDialog.cancel")}
          </Button>
          <Button onClick={handleSave} disabled={pending || !dirty}>
            {pending ? t("editDialog.saving") : t("editDialog.save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
