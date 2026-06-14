// Reads ?error=callback_failed (or similar) from /login URL and pops a
// toast once. The callback route redirects here when a magic-link
// exchange fails (expired, already-used, invalid). Without this the
// user sees no explanation — just the login screen again.

"use client";

import { useEffect } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";

export function LoginErrorToast() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const error = searchParams.get("error");
  const t = useTranslations("login");

  useEffect(() => {
    if (!error) return;
    toast.error(t("callbackError"));
    // Strip the error param after firing so a refresh doesn't re-toast.
    router.replace("/login");
  }, [error, t, router]);

  return null;
}
