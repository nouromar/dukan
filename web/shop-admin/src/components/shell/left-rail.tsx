// Persistent left navigation rail. Order matches docs/shop-admin-portal.md
// § 5.1. Items are filtered by the capability set for the current shop —
// a cashier never sees Setup or Audit because they can't access those
// modules. Mapping picked from migration 0048_capabilities.sql.

"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  LayoutDashboard,
  Receipt,
  PackagePlus,
  Boxes,
  Users,
  Wallet,
  Settings,
  ScrollText,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useShopContext } from "@/lib/shop-context";

type NavItem = {
  href: string;
  /** i18n key under `nav.*`. */
  i18nKey:
    | "overview"
    | "sales"
    | "receives"
    | "inventory"
    | "people"
    | "money"
    | "setup"
    | "audit";
  icon: LucideIcon;
  /** Capability required to see this item. `null` = always visible. */
  capability: string | null;
};

const NAV_ITEMS: readonly NavItem[] = [
  { href: "/overview", i18nKey: "overview", icon: LayoutDashboard, capability: "dashboard.view" },
  { href: "/sales", i18nKey: "sales", icon: Receipt, capability: "sales.history.view" },
  { href: "/receives", i18nKey: "receives", icon: PackagePlus, capability: "receive.history.view" },
  { href: "/inventory", i18nKey: "inventory", icon: Boxes, capability: "inventory.product.view" },
  { href: "/people", i18nKey: "people", icon: Users, capability: "people.party.view" },
  { href: "/money", i18nKey: "money", icon: Wallet, capability: "money.payment.view" },
  { href: "/setup", i18nKey: "setup", icon: Settings, capability: "setup.shop.edit" },
  { href: "/audit", i18nKey: "audit", icon: ScrollText, capability: "audit.view" },
] as const;

export function LeftRail() {
  const pathname = usePathname();
  const { capabilities, currentShop } = useShopContext();
  const t = useTranslations("nav");
  const tApp = useTranslations("app");

  // No shop selected → no nav. The switcher in the top bar surfaces
  // the empty state; left rail just collapses to the brand chip so
  // the layout doesn't shift.
  const visibleItems = currentShop
    ? NAV_ITEMS.filter(
        (item) => item.capability === null || capabilities.has(item.capability),
      )
    : [];

  return (
    <aside className="hidden w-60 shrink-0 border-r bg-sidebar text-sidebar-foreground md:flex md:flex-col">
      <div className="flex h-14 items-center px-4 font-semibold tracking-tight">
        {tApp("name")}
      </div>
      <nav className="flex flex-col gap-1 p-3">
        {visibleItems.map(({ href, i18nKey, icon: Icon }) => {
          const active = pathname?.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                active
                  ? "bg-sidebar-accent text-sidebar-accent-foreground"
                  : "text-sidebar-foreground/80 hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground",
              )}
            >
              <Icon className="size-4" aria-hidden />
              {t(i18nKey)}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
