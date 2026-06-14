// Email magic-link login. Sends a one-time link to the user's inbox;
// clicking it lands on /auth/callback which exchanges the code for a
// session and redirects into the dashboard.
//
// shouldCreateUser: false enforces "account must already exist". Per
// product decision: org/shop is created from the mobile app at first
// signup; the portal is login-only. If the email doesn't match an
// existing auth.users row, Supabase returns a "not allowed" error
// surfaced as emailErrorNoAccount.

"use client";

import { useState } from "react";
import { useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { CheckCircle2 } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

export function EmailForm() {
  const searchParams = useSearchParams();
  const next = searchParams.get("next") ?? "/";
  const t = useTranslations("login");

  const [email, setEmail] = useState("");
  const [sending, setSending] = useState(false);
  const [sentTo, setSentTo] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSending(true);

    const supabase = createSupabaseBrowserClient();
    const redirectTo = `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`;
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        // Account must exist from mobile signup — don't auto-create.
        shouldCreateUser: false,
        emailRedirectTo: redirectTo,
      },
    });

    if (error) {
      // Supabase returns a generic "signups not allowed" when the
      // user doesn't exist. Map to friendlier copy.
      const msg = error.message?.toLowerCase() ?? "";
      if (msg.includes("not allowed") || msg.includes("not found")) {
        toast.error(t("emailErrorNoAccount"));
      } else {
        toast.error(error.message || t("emailErrorGeneric"));
      }
      setSending(false);
      return;
    }

    setSentTo(email);
    setSending(false);
  }

  if (sentTo) {
    return (
      <div className="flex flex-col items-center py-6 text-center">
        <CheckCircle2
          className="mb-3 size-8 text-primary"
          aria-hidden
        />
        <h3 className="text-base font-medium">{t("emailSent")}</h3>
        <p className="mt-2 max-w-xs text-sm text-muted-foreground">
          {t("emailSentBody", { email: sentTo })}
        </p>
      </div>
    );
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      <div className="space-y-2">
        <Label htmlFor="email">{t("emailLabel")}</Label>
        <Input
          id="email"
          type="email"
          inputMode="email"
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder={t("emailPlaceholder")}
          required
        />
        <p className="text-xs text-muted-foreground">{t("emailHelp")}</p>
      </div>
      <Button type="submit" className="w-full" disabled={sending}>
        {sending ? t("emailSending") : t("emailSendLink")}
      </Button>
    </form>
  );
}
