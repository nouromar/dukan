// POST { shopId } — sets the current_shop_id cookie and bounces back
// to the referer (or /). Verified server-side that the user actually
// has access to the shop before persisting, so a curl with someone
// else's shop id can't trick the cookie.

import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const SHOP_COOKIE = "current_shop_id";

export async function POST(request: Request) {
  const formData = await request.formData();
  const shopId = formData.get("shopId");
  const back = (formData.get("back") as string | null) ?? "/";

  if (typeof shopId !== "string" || shopId.length === 0) {
    return new NextResponse("missing shopId", { status: 400 });
  }

  const supabase = await createSupabaseServerClient();
  // RLS on `shop` already filters to the user's accessible shops, so
  // a row only comes back if access is real. Belt-and-suspenders: we
  // also reject if Supabase returns nothing.
  const { data, error } = await supabase
    .from("shop")
    .select("id")
    .eq("id", shopId)
    .maybeSingle();
  if (error || !data) {
    return new NextResponse("forbidden", { status: 403 });
  }

  const response = NextResponse.redirect(new URL(back, request.url), {
    status: 303,
  });
  response.cookies.set(SHOP_COOKIE, shopId, {
    path: "/",
    httpOnly: true,
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 365,
  });
  return response;
}

export { SHOP_COOKIE };
