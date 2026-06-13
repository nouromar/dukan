// Dashboard shell — the persistent left rail + top bar that every
// authenticated screen lives inside. Per docs/shop-admin-portal.md
// § 5.1: 7 nav sections (Overview / Sales / Inventory / People / Money
// / Setup / Audit).
//
// This is a Server Component so the shop list + capability set can be
// fetched on the server in one roundtrip, then handed to client
// components (left rail, shop switcher, capability guards) via
// ShopContextProvider.

import { cookies } from "next/headers";
import { LeftRail } from "@/components/shell/left-rail";
import { TopBar } from "@/components/shell/top-bar";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ShopContextProvider, type Shop } from "@/lib/shop-context";
import { SHOP_COOKIE } from "@/app/auth/select-shop/route";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createSupabaseServerClient();

  // RLS already restricts `shop` to the rows the signed-in user can
  // access; no explicit user-scope filter needed.
  const { data: shopRows } = await supabase
    .from("shop")
    .select("id, name, organization_id")
    .order("name", { ascending: true });
  const shops: Shop[] = shopRows ?? [];

  const cookieStore = await cookies();
  const cookieShopId = cookieStore.get(SHOP_COOKIE)?.value;
  // Resolve current shop: prefer the cookie if it still corresponds to
  // an accessible shop; otherwise fall back to the first shop. If the
  // user has zero shops, currentShop is null and the dashboard renders
  // a "no shops yet" empty state via the switcher.
  const currentShop =
    shops.find((s) => s.id === cookieShopId) ?? shops[0] ?? null;

  let capabilities: string[] = [];
  if (currentShop) {
    const { data: capData } = await supabase.rpc(
      "auth_user_shop_capabilities",
      { p_shop_id: currentShop.id },
    );
    // RPC returns jsonb array<text>; supabase-js parses it for us.
    if (Array.isArray(capData)) {
      capabilities = capData.filter(
        (v): v is string => typeof v === "string",
      );
    }
  }

  return (
    <ShopContextProvider
      shops={shops}
      currentShop={currentShop}
      capabilities={capabilities}
    >
      <div className="flex min-h-screen w-full bg-background">
        <LeftRail />
        <div className="flex flex-1 flex-col">
          <TopBar />
          <main className="flex-1 overflow-y-auto p-6">{children}</main>
        </div>
      </div>
    </ShopContextProvider>
  );
}
