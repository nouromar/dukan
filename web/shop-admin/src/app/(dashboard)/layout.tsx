// Dashboard shell — the persistent left rail + top bar that every
// authenticated screen lives inside. Per docs/shop-admin-portal.md
// § 5.1: 7 nav sections (Overview / Sales / Inventory / People / Money
// / Setup / Audit). Shop switcher in the top bar gets wired in #269;
// for now it's a static placeholder.

import Link from "next/link";
import { LeftRail } from "@/components/shell/left-rail";
import { TopBar } from "@/components/shell/top-bar";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen w-full bg-background">
      <LeftRail />
      <div className="flex flex-1 flex-col">
        <TopBar />
        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}
