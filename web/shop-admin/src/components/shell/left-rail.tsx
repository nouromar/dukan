// Persistent left navigation rail. Order matches docs/shop-admin-portal.md
// § 5.1. Each nav item will be capability-gated in #269 — until then
// every item renders for every user.

"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Receipt,
  Boxes,
  Users,
  Wallet,
  Settings,
  ScrollText,
} from "lucide-react";
import { cn } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/overview", label: "Overview", icon: LayoutDashboard },
  { href: "/sales", label: "Sales", icon: Receipt },
  { href: "/inventory", label: "Inventory", icon: Boxes },
  { href: "/people", label: "People", icon: Users },
  { href: "/money", label: "Money", icon: Wallet },
  { href: "/setup", label: "Setup", icon: Settings },
  { href: "/audit", label: "Audit", icon: ScrollText },
] as const;

export function LeftRail() {
  const pathname = usePathname();
  return (
    <aside className="hidden w-60 shrink-0 border-r bg-sidebar text-sidebar-foreground md:flex md:flex-col">
      <div className="flex h-14 items-center px-4 font-semibold tracking-tight">
        Dukan
      </div>
      <nav className="flex flex-col gap-1 p-3">
        {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
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
              {label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
