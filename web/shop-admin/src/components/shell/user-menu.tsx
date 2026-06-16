// Top-bar user menu. Server component — resolves session identity +
// user_profile display_name + current locale, then delegates the
// interactive panel to UserMenuPanel (client). All the dropdown +
// edit-name dialog state lives in the client side.

import { getLocale } from "next-intl/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { UserMenuPanel } from "@/components/shell/user-menu-panel";
import type { Locale } from "@/i18n/locales";
import { DEFAULT_LOCALE, isLocale } from "@/i18n/locales";

export async function UserMenu() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  let displayName: string | null = null;
  if (user) {
    const { data } = await supabase
      .from("user_profile")
      .select("display_name")
      .eq("user_id", user.id)
      .maybeSingle();
    displayName = data?.display_name ?? null;
  }

  const localeRaw = await getLocale();
  const currentLocale: Locale = isLocale(localeRaw)
    ? localeRaw
    : DEFAULT_LOCALE;

  return (
    <UserMenuPanel
      displayName={displayName}
      phone={user?.phone ?? null}
      currentLocale={currentLocale}
    />
  );
}
