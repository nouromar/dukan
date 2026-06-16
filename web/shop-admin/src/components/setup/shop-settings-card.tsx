// Owner-editable shop settings card on /setup. Three fields today:
// name, currency, default language. Timezone + branding deferred.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { updateShopSettingsAction } from "@/app/(dashboard)/setup/actions";

export type CurrencyOption = { code: string; label: string };
export type LanguageOption = { code: string; label: string };

export function ShopSettingsCard({
  shopId,
  initialName,
  initialCurrencyCode,
  initialLanguageCode,
  currencies,
  languages,
}: {
  shopId: string;
  initialName: string;
  initialCurrencyCode: string;
  initialLanguageCode: string;
  currencies: CurrencyOption[];
  languages: LanguageOption[];
}) {
  const t = useTranslations("setup.shopSettings");
  const router = useRouter();
  const [name, setName] = useState(initialName);
  const [currency, setCurrency] = useState(initialCurrencyCode);
  const [language, setLanguage] = useState(initialLanguageCode);
  const [pending, startTransition] = useTransition();

  const dirty =
    name.trim() !== initialName.trim() ||
    currency !== initialCurrencyCode ||
    language !== initialLanguageCode;

  function handleSave() {
    startTransition(async () => {
      const result = await updateShopSettingsAction({
        shopId,
        name,
        currencyCode: currency,
        defaultLanguageCode: language,
      });
      if (result.ok) {
        toast.success(t("saved"));
        router.refresh();
        return;
      }
      const key = (
        {
          empty: "errorEmpty",
          permission: "errorPermission",
          generic: "errorGeneric",
        } as const
      )[result.code];
      toast.error(t(key as "errorGeneric"));
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-medium">{t("title")}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <Label htmlFor="shop-name">{t("nameLabel")}</Label>
          <Input
            id="shop-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={120}
          />
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label htmlFor="shop-currency">{t("currencyLabel")}</Label>
            <select
              id="shop-currency"
              value={currency}
              onChange={(e) => setCurrency(e.target.value)}
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              {currencies.map((c) => (
                <option key={c.code} value={c.code}>
                  {c.label} ({c.code})
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="shop-language">{t("languageLabel")}</Label>
            <select
              id="shop-language"
              value={language}
              onChange={(e) => setLanguage(e.target.value)}
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
            >
              {languages.map((l) => (
                <option key={l.code} value={l.code}>
                  {l.label}
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="flex justify-end">
          <Button
            onClick={handleSave}
            disabled={pending || !dirty || name.trim().length === 0}
          >
            {pending ? t("saving") : t("save")}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
