// Server-side Supabase client for use in:
//   - Server Components (page.tsx, layout.tsx)
//   - Route Handlers (route.ts)
//   - Server Actions
//
// Reads + writes the session cookie via Next.js's cookies() API so the
// user's auth state survives across requests. Wrap any data fetch that
// must run as the user (RLS-protected reads, posting RPCs) with this
// client, never the browser one.

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { env } from "@/lib/env";

export async function createSupabaseServerClient() {
  const cookieStore = await cookies();
  return createServerClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) => {
              cookieStore.set(name, value, options);
            });
          } catch {
            // setAll in a Server Component throws — Next.js only allows
            // cookie mutations in Server Actions or Route Handlers.
            // Silently swallow; the middleware refreshes the session
            // cookie on the next request.
          }
        },
      },
    },
  );
}
