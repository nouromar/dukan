// Edit Party dialog launched from the detail-page header. Pre-fills
// with current name + phone; auto-saves on submit via Server Action.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
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
import { updatePartyAction } from "@/app/(dashboard)/people/[partyId]/actions";

export function EditPartyDialog({
  shopId,
  partyId,
  initialName,
  initialPhone,
}: {
  shopId: string;
  partyId: string;
  initialName: string;
  initialPhone: string | null;
}) {
  const t = useTranslations("partyDetail");
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(initialName);
  const [phone, setPhone] = useState(initialPhone ?? "");
  const [pending, startTransition] = useTransition();

  function reset() {
    setName(initialName);
    setPhone(initialPhone ?? "");
  }

  function handleSave() {
    startTransition(async () => {
      const result = await updatePartyAction({
        shopId,
        partyId,
        name,
        phoneRaw: phone,
      });
      if (result.ok) {
        toast.success(t("editDialog.saved"));
        setOpen(false);
        router.refresh();
        return;
      }
      const key = (
        {
          missing_name: "editDialog.errorName",
          invalid_phone: "editDialog.errorPhone",
          permission: "editDialog.errorGeneric",
          generic: "editDialog.errorGeneric",
        } as const
      )[result.code];
      toast.error(t(key as "editDialog.errorGeneric"));
    });
  }

  const dirty =
    name.trim() !== initialName.trim() ||
    phone.trim() !== (initialPhone ?? "").trim();

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
            <Label htmlFor="party-name">{t("editDialog.nameLabel")}</Label>
            <Input
              id="party-name"
              type="text"
              autoComplete="name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={200}
              autoFocus
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="party-phone">{t("editDialog.phoneLabel")}</Label>
            <Input
              id="party-phone"
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder={t("editDialog.phonePlaceholder")}
            />
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
          <Button
            onClick={handleSave}
            disabled={pending || !dirty || name.trim().length === 0}
          >
            {pending ? t("editDialog.saving") : t("editDialog.save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
