"use client";

import { useState, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
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

  // Defensive: missing phone param → back to /login.
  useEffect(() => {
    if (!phone) router.replace("/login");
  }, [phone, router]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (code.length !== 6) {
      toast.error("Code is 6 digits.");
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
      toast.error(error.message || "That code didn't work. Try again.");
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
        <CardTitle>Enter your code</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="space-y-4" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="code">6-digit code</Label>
            <Input
              id="code"
              type="text"
              inputMode="numeric"
              pattern="[0-9]{6}"
              maxLength={6}
              autoComplete="one-time-code"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              placeholder="123456"
              required
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              Sent to <span className="font-medium">{phone}</span>.{" "}
              <button
                type="button"
                className="text-primary underline-offset-2 hover:underline"
                onClick={() => router.push("/login")}
              >
                Wrong number?
              </button>
            </p>
          </div>
          <Button type="submit" className="w-full" disabled={verifying}>
            {verifying ? "Verifying…" : "Sign in"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
