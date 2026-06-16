// General tab — shop-level settings (name, currency, default language).
// Capability-gated by setup.shop.edit; cashiers see the tab but no card.

import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Can } from "@/components/auth/can";
import {
  ShopSettingsCard,
  type CurrencyOption,
  type LanguageOption,
} from "@/components/setup/shop-settings-card";

export default async function SetupGeneralPage() {
  const { currentShop } = await getCurrentShop();
  if (!currentShop) return null;

  const supabase = await createSupabaseServerClient();
  const [currenciesRes, languagesRes] = await Promise.all([
    supabase.from("currency").select("code, symbol").order("code"),
    supabase.from("language").select("code, name").order("code"),
  ]);

  const currencies: CurrencyOption[] = (
    (currenciesRes.data ?? []) as Array<{
      code: string;
      symbol: string | null;
    }>
  ).map((c) => ({ code: c.code, label: c.symbol ?? c.code }));
  const languages: LanguageOption[] = (
    (languagesRes.data ?? []) as Array<{ code: string; name: string }>
  ).map((l) => ({ code: l.code, label: l.name }));

  return (
    <Can capability="setup.shop.edit">
      <ShopSettingsCard
        shopId={currentShop.id}
        initialName={currentShop.name}
        initialCurrencyCode={currentShop.currency_code}
        initialLanguageCode={currentShop.default_language_code ?? "en"}
        currencies={currencies}
        languages={languages}
      />
    </Can>
  );
}
