// Session refresh helper called from middleware.ts on every request.
// Without this, the session JWT silently expires and the user gets
// 401s mid-session.

import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { env } from "@/lib/env";

const PUBLIC_ROUTES = ["/login", "/login/verify"];

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => {
            request.cookies.set(name, value);
          });
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => {
            response.cookies.set(name, value, options);
          });
        },
      },
    },
  );

  // Refresh the session in the background. Don't await elsewhere — the
  // cookies set above will be passed back to the browser on the response.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const pathname = request.nextUrl.pathname;
  const isPublic = PUBLIC_ROUTES.some(
    (route) => pathname === route || pathname.startsWith(`${route}/`),
  );

  // Unauthenticated requests to protected routes redirect to /login,
  // preserving the originally-requested path so we can land them there
  // after sign-in.
  if (!user && !isPublic) {
    const loginUrl = new URL("/login", request.url);
    if (pathname !== "/") {
      loginUrl.searchParams.set("next", pathname);
    }
    return NextResponse.redirect(loginUrl);
  }

  // Authenticated users on /login get bounced to the dashboard.
  if (user && isPublic) {
    return NextResponse.redirect(new URL("/", request.url));
  }

  return response;
}
