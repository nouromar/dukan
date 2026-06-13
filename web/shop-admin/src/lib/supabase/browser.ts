// Browser-side Supabase client for use in Client Components only.
// Never import this from a Server Component — it ships JS to the client
// and reads cookies via document.cookie, neither of which makes sense
// on the server.

"use client";

import { createBrowserClient } from "@supabase/ssr";
import { env } from "@/lib/env";

export function createSupabaseBrowserClient() {
  return createBrowserClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
}
