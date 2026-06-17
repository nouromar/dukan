// Owner-only void action on the receive detail page. Mirrors
// VoidSaleButton from #277. The capability gate at the page level
// is the friendly hide; void_receive RPC enforces server-side.

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
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { voidReceiveAction } from "@/app/(dashboard)/receives/[txnId]/actions";

export function VoidReceiveButton({
  shopId,
  txnId,
}: {
  shopId: string;
  txnId: string;
}) {
  const t = useTranslations("receiveDetail");
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [pending, startTransition] = useTransition();

  function handleConfirm() {
    startTransition(async () => {
      const result = await voidReceiveAction({ shopId, txnId, reason });
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
          <Label htmlFor="void-rcv-reason">{t("voidDialog.reasonLabel")}</Label>
          <Textarea
            id="void-rcv-reason"
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
