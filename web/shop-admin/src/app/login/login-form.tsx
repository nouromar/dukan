"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { defaultCountryCode } from "shared";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { normalizePhoneNumber, PhoneFormatError } from "@/lib/phone";

export function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get("next") ?? "/";
  const t = useTranslations("login");

  const [phone, setPhone] = useState(defaultCountryCode);
  const [sending, setSending] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSending(true);
    let normalized: string;
    try {
      normalized = normalizePhoneNumber(phone);
    } catch (err) {
      if (err instanceof PhoneFormatError) {
        toast.error(t("errorPhone"));
      } else {
        toast.error(t("errorGeneric"));
      }
      setSending(false);
      return;
    }

    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase.auth.signInWithOtp({
      phone: normalized,
    });

    if (error) {
      toast.error(error.message || t("errorSend"));
      setSending(false);
      return;
    }

    const params = new URLSearchParams({ phone: normalized, next });
    router.push(`/login/verify?${params.toString()}`);
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("title")}</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="space-y-4" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="phone">{t("phoneLabel")}</Label>
            <Input
              id="phone"
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder={t("phonePlaceholder")}
              required
            />
            <p className="text-xs text-muted-foreground">{t("phoneHelp")}</p>
          </div>
          <Button type="submit" className="w-full" disabled={sending}>
            {sending ? t("sending") : t("sendCode")}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
