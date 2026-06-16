// Client side of UserMenu. Owns the dropdown trigger + the
// Edit Name dialog state. The parent UserMenu (server component)
// resolves identity info (user id, current display name, phone,
// language) and hands it down via props.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { User as UserIcon, Check, Pencil } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { LOCALES, LOCALE_LABELS, type Locale } from "@/i18n/locales";
import { updateMyProfileAction } from "@/app/(dashboard)/setup/actions";

export function UserMenuPanel({
  displayName,
  phone,
  currentLocale,
}: {
  /** Resolved user_profile.display_name; null when unset. */
  displayName: string | null;
  /** auth.users.phone; null when unset. */
  phone: string | null;
  currentLocale: Locale;
}) {
  const t = useTranslations("userMenu");
  const router = useRouter();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [draftName, setDraftName] = useState(displayName ?? "");
  const [pending, startTransition] = useTransition();

  // The trigger label: prefer display_name, fall back to phone, then dash.
  const triggerLabel = displayName ?? phone ?? "—";

  function handleEditClick() {
    setDraftName(displayName ?? "");
    setDialogOpen(true);
  }

  function handleSave() {
    startTransition(async () => {
      const result = await updateMyProfileAction({ displayName: draftName });
      if (result.ok) {
        toast.success(t("nameDialog.saved"));
        setDialogOpen(false);
        router.refresh();
        return;
      }
      const key =
        result.code === "empty" ? "errorEmpty" : "errorGeneric";
      toast.error(t(`nameDialog.${key}` as "nameDialog.errorGeneric"));
    });
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger
          className={cn(
            buttonVariants({ variant: "ghost", size: "sm" }),
            "gap-2",
          )}
        >
          <UserIcon className="size-4" aria-hidden />
          <span className="max-w-[180px] truncate text-sm">
            {triggerLabel}
          </span>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-60">
          <DropdownMenuGroup>
            <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">
              {t("signedInAs")}
            </DropdownMenuLabel>
            <DropdownMenuLabel className="pt-0 text-sm">
              {triggerLabel}
            </DropdownMenuLabel>
            <DropdownMenuItem onClick={handleEditClick}>
              <Pencil className="size-3.5" aria-hidden />
              <span>{t("editName")}</span>
            </DropdownMenuItem>
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuGroup>
            <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">
              {t("language")}
            </DropdownMenuLabel>
            {LOCALES.map((loc) => {
              const active = loc === currentLocale;
              return (
                <DropdownMenuItem key={loc}>
                  <form
                    action="/auth/set-locale"
                    method="post"
                    className="w-full"
                  >
                    <input type="hidden" name="locale" value={loc} />
                    <button
                      type="submit"
                      className="flex w-full items-center justify-between text-left"
                    >
                      <span>{LOCALE_LABELS[loc]}</span>
                      {active ? (
                        <Check
                          className="size-4 text-primary"
                          aria-label="Selected"
                        />
                      ) : null}
                    </button>
                  </form>
                </DropdownMenuItem>
              );
            })}
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuItem>
            <form action="/auth/signout" method="post" className="w-full">
              <button type="submit" className="w-full text-left">
                {t("signOut")}
              </button>
            </form>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("nameDialog.title")}</DialogTitle>
            <DialogDescription>
              {t("nameDialog.description")}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="display-name">{t("nameDialog.label")}</Label>
            <Input
              id="display-name"
              value={draftName}
              onChange={(e) => setDraftName(e.target.value)}
              placeholder={t("nameDialog.placeholder")}
              maxLength={120}
              autoFocus
            />
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setDialogOpen(false)}
              disabled={pending}
            >
              {t("nameDialog.cancel")}
            </Button>
            <Button
              onClick={handleSave}
              disabled={
                pending ||
                draftName.trim().length === 0 ||
                draftName.trim() === (displayName ?? "")
              }
            >
              {pending ? t("nameDialog.saving") : t("nameDialog.save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
