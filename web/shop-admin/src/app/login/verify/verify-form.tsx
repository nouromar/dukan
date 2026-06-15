"use client";

import { useState, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

export function VerifyForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const phone = searchParams.get("phone") ?? "";
  const next = searchParams.get("next") ?? "/";
  const [code, setCode] = useState("");
  const [verifying, setVerifying] = useState(false);
  const t = useTranslations("verify");

  // Defensive: missing phone param → back to /login.
  useEffect(() => {
    if (!phone) router.replace("/login");
  }, [phone, router]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (code.length < 6 || code.length > 10) {
      toast.error(t("errorLength"));
      return;
    }
    setVerifying(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase.auth.verifyOtp({
      phone,
      token: code,
      type: "sms",
    });
    if (error) {
      toast.error(error.message || t("errorVerify"));
      setVerifying(false);
      return;
    }
    // Hard refresh so middleware picks up the new session cookie before
    // routing into the dashboard.
    window.location.assign(next);
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("title")}</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="space-y-4" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="code">{t("codeLabel")}</Label>
            <Input
              id="code"
              type="text"
              // Supabase OTP length is 6–10 in project settings, and the
              // format can be alphanumeric — accept both, trim
              // whitespace, don't strip non-digits.
              inputMode="text"
              maxLength={10}
              autoComplete="one-time-code"
              value={code}
              onChange={(e) => setCode(e.target.value.trim())}
              placeholder={t("codePlaceholder")}
              required
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              {t("sentTo", { phone })}{" "}
              <button
                type="button"
                className="text-primary underline-offset-2 hover:underline"
                onClick={() => router.push("/login")}
              >
                {t("wrongNumber")}
              </button>
            </p>
          </div>
          <Button type="submit" className="w-full" disabled={verifying}>
            {verifying ? t("verifying") : t("submit")}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
