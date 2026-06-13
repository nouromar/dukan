// Top bar — shop switcher + search (#271 / global) + user menu.
// Server component so the user menu can read the session via
// createSupabaseServerClient without shipping the SDK to the client.

import { Search } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Input } from "@/components/ui/input";
import { UserMenu } from "@/components/shell/user-menu";
import { ShopSwitcher } from "@/components/shell/shop-switcher";

export async function TopBar() {
  const t = await getTranslations("topBar");
  return (
    <header className="flex h-14 items-center gap-4 border-b bg-background px-6">
      <ShopSwitcher />
      <div className="relative ml-auto w-full max-w-sm">
        <Search
          className="pointer-events-none absolute left-2.5 top-2.5 size-4 text-muted-foreground"
          aria-hidden
        />
        <Input
          type="search"
          placeholder={t("searchPlaceholder")}
          className="pl-8"
          disabled
          aria-label={t("searchPlaceholder")}
        />
      </div>
      <UserMenu />
    </header>
  );
}
