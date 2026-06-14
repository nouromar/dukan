// Dashboard shell — the persistent left rail + top bar that every
// authenticated screen lives inside. Per docs/shop-admin-portal.md
// § 5.1: 7 nav sections (Overview / Sales / Inventory / People / Money
// / Setup / Audit).
//
// Shop + capability resolution is delegated to getCurrentShop() so
// module pages can call it again without a second RPC roundtrip
// (React `cache` dedupes within a request).

import { LeftRail } from "@/components/shell/left-rail";
import { TopBar } from "@/components/shell/top-bar";
import { ShopContextProvider } from "@/lib/shop-context";
import { getCurrentShop } from "@/lib/current-shop";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { shops, currentShop, capabilities } = await getCurrentShop();

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
