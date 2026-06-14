// GET /auth/callback — handles the magic-link click from the email
// Supabase sent. Exchanges the ?code= for a session cookie, then
// redirects into the dashboard (or wherever ?next= says).
//
// Supabase project config required for this to work in production:
//   Authentication → URL Configuration → Site URL:
//     https://dukan-shop-admin.vercel.app
//   Authentication → URL Configuration → Redirect URLs (add):
//     https://dukan-shop-admin.vercel.app/auth/callback
//     http://localhost:3010/auth/callback   (for local dev)

import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const next = url.searchParams.get("next") ?? "/";

  if (!code) {
    // Direct hit / stale link → bounce back to login with a hint.
    return NextResponse.redirect(
      new URL("/login?error=missing_code", request.url),
      { status: 303 },
    );
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(
      new URL("/login?error=callback_failed", request.url),
      { status: 303 },
    );
  }

  return NextResponse.redirect(new URL(next, request.url), { status: 303 });
}
