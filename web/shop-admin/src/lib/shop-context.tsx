// Cross-cutting state for the dashboard: list of shops the signed-in
// user can access, which one is currently selected, and the capability
// set for that shop. Populated server-side in (dashboard)/layout.tsx
// from a single roundtrip; consumed by client components via hooks.
//
// Why a context, not per-component fetches: a typical dashboard view
// needs the capability set in 3+ places (left rail, page guard, action
// menus). Fetching once per render avoids fan-out network calls and
// keeps every consumer in sync after a shop switch.

"use client";

import { createContext, useContext, useMemo } from "react";

export type Shop = {
  id: string;
  name: string;
  organization_id: string;
};

export type ShopContextValue = {
  shops: Shop[];
  currentShop: Shop | null;
  /** Capability codes for the *current* shop. Set is O(1) for has(). */
  capabilities: Set<string>;
};

const ShopContext = createContext<ShopContextValue | null>(null);

export function ShopContextProvider({
  shops,
  currentShop,
  capabilities,
  children,
}: {
  shops: Shop[];
  currentShop: Shop | null;
  capabilities: string[];
  children: React.ReactNode;
}) {
  const value = useMemo<ShopContextValue>(
    () => ({
      shops,
      currentShop,
      capabilities: new Set(capabilities),
    }),
    [shops, currentShop, capabilities],
  );
  return <ShopContext.Provider value={value}>{children}</ShopContext.Provider>;
}

export function useShopContext(): ShopContextValue {
  const ctx = useContext(ShopContext);
  if (!ctx) {
    throw new Error(
      "useShopContext must be used inside <ShopContextProvider>. " +
        "Did you render a component outside the dashboard layout?",
    );
  }
  return ctx;
}

/** Returns true if the current shop's capability set contains `code`. */
export function useCapability(code: string): boolean {
  return useShopContext().capabilities.has(code);
}
