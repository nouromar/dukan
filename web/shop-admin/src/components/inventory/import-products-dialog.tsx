// CSV importer for products. Same shape as ImportPartiesDialog but
// against importProductsAction. Locale carried into the action so
// the seeded display alias gets the right language tag.

"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations, useLocale } from "next-intl";
import { toast } from "sonner";
import { Upload } from "lucide-react";
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
import { cn } from "@/lib/utils";
import { importProductsAction } from "@/app/(dashboard)/inventory/actions";

export function ImportProductsDialog({ shopId }: { shopId: string }) {
  const t = useTranslations("inventory.importDialog");
  const tButton = useTranslations("inventory");
  const locale = useLocale();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [pending, startTransition] = useTransition();

  function reset() {
    setFile(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  }

  function handleConfirm() {
    if (!file) {
      toast.error(t("noFile"));
      return;
    }
    startTransition(async () => {
      const fd = new FormData();
      fd.append("shopId", shopId);
      fd.append("file", file);
      fd.append("languageCode", locale);
      const result = await importProductsAction(fd);
      if (result.ok) {
        toast.success(
          t("success", { created: result.created, skipped: result.skipped }),
        );
        if (result.skippedReasons.length > 0) {
          for (const r of result.skippedReasons.slice(0, 5)) {
            toast.error(t("errorPattern", { row: r.row, reason: r.reason }));
          }
        }
        setOpen(false);
        reset();
        router.refresh();
        return;
      }
      const key = result.code === "permission" ? "errorPermission" : "errorGeneric";
      toast.error(t(key as "errorGeneric"));
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
        <Upload className="size-4" aria-hidden />
        {tButton("importButton")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("title")}</DialogTitle>
          <DialogDescription>{t("description")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <Label htmlFor="csv-products">{t("fileLabel")}</Label>
          <input
            id="csv-products"
            ref={fileInputRef}
            type="file"
            accept=".csv,text/csv"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            className="block w-full text-sm file:mr-3 file:rounded-md file:border file:border-input file:bg-background file:px-3 file:py-1 file:text-sm file:font-medium"
          />
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => setOpen(false)}
            disabled={pending}
          >
            {t("cancel")}
          </Button>
          <Button onClick={handleConfirm} disabled={pending || !file}>
            {pending ? t("submitting") : t("confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
