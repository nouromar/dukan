// Add Staff dialog. Layout:
//
//   ┌──────────────────────────────────────┐
//   │ Add staff                            │
//   │ They'll see the shop next sign-in.   │
//   ├──────────────────────────────────────┤
//   │                                      │
//   │ Name                                 │
//   │ [____________________________]       │
//   │ Optional — they can change later.    │
//   │                                      │
//   │ ─── Sign in with ──────              │
//   │ 📱 [+252612345678_____________]      │
//   │ ✉️  [name@example.com___________]    │
//   │ Phone, email, or both.               │
//   │                                      │
//   │ Role  [Cashier ▾]                    │
//   │                                      │
//   │            [Cancel] [Add staff]      │
//   └──────────────────────────────────────┘
//
// The cashier uses whichever channel they prefer to sign in; the
// auto-claim RPC matches on either and creates their membership.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { UserPlus, Phone, Mail } from "lucide-react";
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
  const [displayName, setDisplayName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("cashier");
  const [pending, startTransition] = useTransition();

  const canSubmit =
    !pending && (phone.trim() !== "" || email.trim() !== "");

  function reset() {
    setPhone("");
    setEmail("");
    setRole("cashier");
    setDisplayName("");
  }

  function handleConfirm() {
    startTransition(async () => {
      const result = await addStaffAction({
        shopId,
        phoneRaw: phone,
        emailRaw: email,
        roleCode: role,
        displayName,
      });
      if (result.ok) {
        toast.success(
          t("addDialog.success", { name: result.displayLabel }),
        );
        setOpen(false);
        reset();
        router.refresh();
        return;
      }
      const errorKey = (
        {
          missing_contact: "addDialog.errorMissingContact",
          invalid_phone: "addDialog.errorInvalidPhone",
          invalid_email: "addDialog.errorInvalidEmail",
          permission: "addDialog.errorPermission",
          conflict: "addDialog.errorConflict",
          generic: "addDialog.errorGeneric",
        } as const
      )[result.code];
      toast.error(t(errorKey as "addDialog.errorGeneric"));
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

        <div className="space-y-5">
          {/* Name */}
          <div className="space-y-1.5">
            <Label htmlFor="staff-name">{t("addDialog.nameLabel")}</Label>
            <Input
              id="staff-name"
              type="text"
              autoComplete="name"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder={t("addDialog.namePlaceholder")}
              maxLength={120}
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              {t("addDialog.nameHelp")}
            </p>
          </div>

          {/* Sign-in channels (grouped) */}
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                {t("addDialog.signInWith")}
              </span>
              <div className="h-px flex-1 bg-border" aria-hidden />
            </div>
            <div className="space-y-2">
              <IconInput
                id="staff-phone"
                icon={Phone}
                type="tel"
                inputMode="tel"
                autoComplete="tel"
                value={phone}
                onChange={setPhone}
                placeholder={t("addDialog.phonePlaceholder")}
              />
              <IconInput
                id="staff-email"
                icon={Mail}
                type="email"
                inputMode="email"
                autoComplete="email"
                value={email}
                onChange={setEmail}
                placeholder={t("addDialog.emailPlaceholder")}
              />
            </div>
            <p className="text-xs text-muted-foreground">
              {t("addDialog.contactHint")}
            </p>
          </div>

          {/* Role */}
          <div className="flex items-center gap-3">
            <Label htmlFor="role" className="shrink-0">
              {t("addDialog.roleLabel")}
            </Label>
            <select
              id="role"
              value={role}
              onChange={(e) => setRole(e.target.value as Role)}
              className="flex h-9 flex-1 rounded-md border border-input bg-background px-3 py-1 text-sm"
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
          <Button onClick={handleConfirm} disabled={!canSubmit}>
            {pending ? t("addDialog.submitting") : t("addDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function IconInput({
  id,
  icon: Icon,
  type,
  inputMode,
  autoComplete,
  value,
  onChange,
  placeholder,
}: {
  id: string;
  icon: React.ComponentType<{ className?: string }>;
  type: string;
  inputMode: "tel" | "email" | "text";
  autoComplete: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
}) {
  return (
    <div className="relative">
      <Icon
        className="pointer-events-none absolute left-3 top-2.5 size-4 text-muted-foreground"
        aria-hidden
      />
      <Input
        id={id}
        type={type}
        inputMode={inputMode}
        autoComplete={autoComplete}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="pl-9"
      />
    </div>
  );
}
