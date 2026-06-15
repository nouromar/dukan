// Add Staff dialog — single contact field (phone OR email, auto-
// detected) + role select. Client component: form state + transition.
// Capability-gate (setup.staff.invite) is enforced at the page level,
// so this component assumes the viewer is allowed to invite.

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
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { addStaffAction } from "@/app/(dashboard)/setup/actions";

type Role = "cashier" | "owner";

export function AddStaffDialog({ shopId }: { shopId: string }) {
  const t = useTranslations("setup");
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [contact, setContact] = useState("");
  const [role, setRole] = useState<Role>("cashier");
  const [pending, startTransition] = useTransition();

  function handleConfirm() {
    startTransition(async () => {
      const result = await addStaffAction({
        shopId,
        contact,
        roleCode: role,
      });
      if (result.ok) {
        const messageKey =
          result.channel === "phone"
            ? "addDialog.successPhone"
            : "addDialog.successEmail";
        toast.success(
          t(
            messageKey as "addDialog.successPhone",
            result.channel === "phone"
              ? { phone: result.value }
              : { email: result.value },
          ),
        );
        setOpen(false);
        setContact("");
        setRole("cashier");
        router.refresh();
        return;
      }
      const errorKey = (
        {
          invalid_contact: "addDialog.errorInvalidContact",
          permission: "addDialog.errorPermission",
          generic: "addDialog.errorGeneric",
        } as const
      )[result.code];
      toast.error(t(errorKey as "addDialog.errorGeneric"));
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        className={cn(buttonVariants({ size: "sm" }), "gap-2")}
      >
        <UserPlus className="size-4" aria-hidden />
        {t("staff.addButton")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("addDialog.title")}</DialogTitle>
          <DialogDescription>{t("addDialog.description")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="contact">{t("addDialog.contactLabel")}</Label>
            <Input
              id="contact"
              type="text"
              inputMode="text"
              autoComplete="off"
              value={contact}
              onChange={(e) => setContact(e.target.value)}
              placeholder={t("addDialog.contactPlaceholder")}
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              {t("addDialog.contactHelp")}
            </p>
          </div>
          <div className="space-y-2">
            <Label htmlFor="role">{t("addDialog.roleLabel")}</Label>
            <select
              id="role"
              value={role}
              onChange={(e) => setRole(e.target.value as Role)}
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              <option value="cashier">{t("addDialog.roleCashier")}</option>
              <option value="owner">{t("addDialog.roleOwner")}</option>
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
            disabled={pending || contact.trim().length === 0}
          >
            {pending ? t("addDialog.submitting") : t("addDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
