// Owner-only void action on the sale detail page. Confirms via a
// dialog with a required reason input, then calls the voidSaleAction
// Server Action. Surfaces structured error codes as friendly toasts.
//
// The button is hidden by <Can capability="setup.shop.edit"> at the
// page level — only owners see it. Server-side, void_sale RPC
// enforces the same constraint regardless of what the client tries.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
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
import { cn } from "@/lib/utils";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { voidSaleAction } from "@/app/(dashboard)/sales/[txnId]/actions";

export function VoidSaleButton({
  shopId,
  txnId,
}: {
  shopId: string;
  txnId: string;
}) {
  const t = useTranslations("saleDetail");
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [pending, startTransition] = useTransition();

  async function handleConfirm() {
    startTransition(async () => {
      const result = await voidSaleAction({ shopId, txnId, reason });
      if (result.ok) {
        toast.success(t("voidSuccess"));
        setOpen(false);
        setReason("");
        router.refresh();
        return;
      }
      const key = (
        {
          missing_reason: "reasonRequired",
          not_owner: "ownerOnly",
          window_expired: "windowExpired",
          already_voided: "alreadyVoided",
          generic: "errorGeneric",
        } as const
      )[result.code];
      toast.error(t(`voidDialog.${key}` as "voidDialog.errorGeneric"));
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        className={cn(
          buttonVariants({ variant: "destructive", size: "sm" }),
          "gap-2",
        )}
      >
        <Trash2 className="size-4" aria-hidden />
        {t("voidButton")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("voidDialog.title")}</DialogTitle>
          <DialogDescription>{t("voidDialog.description")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <Label htmlFor="void-reason">{t("voidDialog.reasonLabel")}</Label>
          <Textarea
            id="void-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder={t("voidDialog.reasonPlaceholder")}
            rows={3}
            required
          />
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => setOpen(false)}
            disabled={pending}
          >
            {t("voidDialog.cancel")}
          </Button>
          <Button
            variant="destructive"
            onClick={handleConfirm}
            disabled={pending || reason.trim().length === 0}
          >
            {pending ? t("voidDialog.submitting") : t("voidDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
