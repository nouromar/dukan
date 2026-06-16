// Horizontal tab strip for the Setup module. Underline-style active
// state matches the Money module's tab pattern (which uses url-driven
// tabs too, see /money). Anchor tags so the user can middle-click or
// open in a new tab.

"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import { cn } from "@/lib/utils";

const TABS = [
  { href: "/setup/general", key: "general" },
  { href: "/setup/staff", key: "staff" },
  { href: "/setup/invites", key: "invites" },
] as const;

export function SetupTabs() {
  const t = useTranslations("setup.tabs");
  const pathname = usePathname();

  return (
    <nav className="border-b">
      <ul className="flex gap-1">
        {TABS.map((tab) => {
          const active = pathname?.startsWith(tab.href);
          return (
            <li key={tab.href}>
              <Link
                href={tab.href}
                className={cn(
                  "inline-flex h-9 items-center border-b-2 px-3 text-sm font-medium transition-colors",
                  active
                    ? "border-primary text-foreground"
                    : "border-transparent text-muted-foreground hover:text-foreground",
                )}
              >
                {t(tab.key)}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
