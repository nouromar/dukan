// POST { locale, back? } — set the locale cookie and redirect back.
// Locale is validated against our supported set; an unknown locale
// returns 400 rather than silently falling back, so config errors are
// visible.

import { NextResponse } from "next/server";
import { LOCALE_COOKIE, isLocale } from "@/i18n/locales";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  const formData = await request.formData();
  const locale = formData.get("locale");
  const back = (formData.get("back") as string | null) ?? "/";

  if (!isLocale(locale)) {
    return new NextResponse("invalid locale", { status: 400 });
  }

  // Write-through to user_preference so the choice rides across
  // devices. Best-effort: if the upsert fails (user not signed in,
  // network blip), we still set the cookie so the *current* device
  // works. The next sign-in on another device will fall back to the
  // default until the user toggles again.
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) {
    await supabase
      .from("user_preference")
      .upsert(
        { user_id: user.id, locale },
        { onConflict: "user_id" },
      );
  }

  const response = NextResponse.redirect(new URL(back, request.url), {
    status: 303,
  });
  response.cookies.set(LOCALE_COOKIE, locale, {
    path: "/",
    httpOnly: false,
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 365,
  });
  return response;
}
