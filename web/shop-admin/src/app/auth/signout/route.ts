// Sign-out hits this Route Handler so we can call supabase.auth.signOut()
// (which needs server-side cookie writes) and then redirect, without
// shipping the supabase client JS to the user menu component.

import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  return NextResponse.redirect(new URL("/login", request.url), {
    status: 303,
  });
}
