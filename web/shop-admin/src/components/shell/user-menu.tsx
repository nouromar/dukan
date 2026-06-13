import { User as UserIcon, Check } from "lucide-react";
import { getTranslations, getLocale } from "next-intl/server";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { buttonVariants } from "@/components/ui/button";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";
import { LOCALES, LOCALE_LABELS, type Locale } from "@/i18n/locales";

export async function UserMenu() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const phone = user?.phone ?? "—";
  const t = await getTranslations("userMenu");
  const currentLocale = await getLocale();
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          buttonVariants({ variant: "ghost", size: "sm" }),
          "gap-2",
        )}
      >
        <UserIcon className="size-4" aria-hidden />
        <span className="max-w-[140px] truncate text-sm">{phone}</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuGroup>
          <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">
            {t("signedInAs")}
          </DropdownMenuLabel>
          <DropdownMenuLabel className="pt-0 text-sm">
            {phone}
          </DropdownMenuLabel>
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuGroup>
          <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">
            {t("language")}
          </DropdownMenuLabel>
          {LOCALES.map((loc: Locale) => {
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
  );
}
