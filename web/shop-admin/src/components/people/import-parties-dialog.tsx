// Single-shot CSV importer. Uploads a file, parses + creates rows
// server-side, reports a summary toast. No preview step in v1 — if
// the summary shows skipped rows the user can fix the CSV and re-
// upload. Skipped rows logged to dev console for debugging.

"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
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
import { importPartiesAction } from "@/app/(dashboard)/people/actions";

export function ImportPartiesDialog({ shopId }: { shopId: string }) {
  const t = useTranslations("people.importDialog");
  const tButton = useTranslations("people");
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
      const result = await importPartiesAction(fd);
      if (result.ok) {
        toast.success(
          t("success", {
            created: result.created,
            skipped: result.skipped,
          }),
        );
        if (result.skippedReasons.length > 0) {
          // Surface a few per-row failures so the user can fix the
          // CSV. Cap at 5 to keep the toast tray sane.
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
          <Label htmlFor="csv-file">{t("fileLabel")}</Label>
          <input
            id="csv-file"
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
