// Add Party dialog launched from the /people header. Three fields:
// name (required), phone (optional, +252 normalized), type
// (customer/supplier select).

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { UserPlus } from "lucide-react";
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
import { addPartyAction } from "@/app/(dashboard)/people/actions";

type PartyType = "customer" | "supplier";

export function AddPartyDialog({ shopId }: { shopId: string }) {
  const t = useTranslations("people");
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [type, setType] = useState<PartyType>("customer");
  const [pending, startTransition] = useTransition();

  function reset() {
    setName("");
    setPhone("");
    setType("customer");
  }

  function handleConfirm() {
    startTransition(async () => {
      const result = await addPartyAction({
        shopId,
        name,
        phoneRaw: phone,
        typeCode: type,
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
          invalid_phone: "addDialog.errorPhone",
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
        <UserPlus className="size-4" aria-hidden />
        {t("addButton")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("addDialog.title")}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="party-name">{t("addDialog.nameLabel")}</Label>
            <Input
              id="party-name"
              type="text"
              autoComplete="name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("addDialog.namePlaceholder")}
              maxLength={200}
              autoFocus
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="party-phone">{t("addDialog.phoneLabel")}</Label>
            <Input
              id="party-phone"
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder={t("addDialog.phonePlaceholder")}
            />
            <p className="text-xs text-muted-foreground">
              {t("addDialog.phoneHelp")}
            </p>
          </div>
          <div className="flex items-center gap-3">
            <Label htmlFor="party-type" className="shrink-0">
              {t("addDialog.typeLabel")}
            </Label>
            <select
              id="party-type"
              value={type}
              onChange={(e) => setType(e.target.value as PartyType)}
              className="flex h-9 flex-1 rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              <option value="customer">{t("addDialog.typeCustomer")}</option>
              <option value="supplier">{t("addDialog.typeSupplier")}</option>
            </select>
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
            disabled={pending || name.trim().length === 0}
          >
            {pending ? t("addDialog.submitting") : t("addDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
