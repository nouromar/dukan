"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
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
        toast.error("Enter a valid phone number, for example +252612345678.");
      } else {
        toast.error("Something went wrong. Try again.");
      }
      setSending(false);
      return;
    }

    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase.auth.signInWithOtp({
      phone: normalized,
    });

    if (error) {
      toast.error(error.message || "Could not send the code. Try again.");
      setSending(false);
      return;
    }

    const params = new URLSearchParams({ phone: normalized, next });
    router.push(`/login/verify?${params.toString()}`);
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sign in</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="space-y-4" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="phone">Phone number</Label>
            <Input
              id="phone"
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+252612345678"
              required
            />
            <p className="text-xs text-muted-foreground">
              We&apos;ll text you a 6-digit code.
            </p>
          </div>
          <Button type="submit" className="w-full" disabled={sending}>
            {sending ? "Sending…" : "Send code"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
