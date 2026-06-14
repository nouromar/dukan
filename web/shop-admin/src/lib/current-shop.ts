// Server-side shop resolution. The dashboard layout (page wrapper)
// needs it to populate ShopContextProvider; module pages need it again
// to fetch shop-scoped data. Wrapped in React `cache` so multiple
// callers within one request share a single shops fetch + capability
// fetch — no double roundtrips.

import { cache } from "react";
import { cookies } from "next/headers";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SHOP_COOKIE } from "@/app/auth/select-shop/route";
import type { Shop } from "@/lib/shop-context";

export type CurrentShopResult = {
  shops: Shop[];
  currentShop: Shop | null;
  capabilities: string[];
};

/**
 * Resolves the signed-in user's shop list, the currently-selected
 * shop (from cookie, falling back to first), and the capability set
 * for that shop. Returns empty defaults when the user has no shops
 * yet — callers render an empty state in that case.
 */
export const getCurrentShop = cache(async (): Promise<CurrentShopResult> => {
  const supabase = await createSupabaseServerClient();

  const { data: shopRows } = await supabase
    .from("shop")
    .select("id, name, organization_id, currency_code")
    .order("name", { ascending: true });
  const shops: Shop[] = shopRows ?? [];

  const cookieStore = await cookies();
  const cookieShopId = cookieStore.get(SHOP_COOKIE)?.value;
  const currentShop =
    shops.find((s) => s.id === cookieShopId) ?? shops[0] ?? null;

  let capabilities: string[] = [];
  if (currentShop) {
    const { data: capData } = await supabase.rpc(
      "auth_user_shop_capabilities",
      { p_shop_id: currentShop.id },
    );
    if (Array.isArray(capData)) {
      capabilities = capData.filter(
        (v): v is string => typeof v === "string",
      );
    }
  }

  return { shops, currentShop, capabilities };
});
