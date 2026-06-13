// Capability guard. Renders children only if the current shop's
// capability set includes the named code. Optional `fallback` for
// "you can't do this" placeholders; default is to render nothing so
// menus and toolbars collapse cleanly.

"use client";

import { useCapability } from "@/lib/shop-context";

export function Can({
  capability,
  fallback = null,
  children,
}: {
  capability: string;
  fallback?: React.ReactNode;
  children: React.ReactNode;
}) {
  const allowed = useCapability(capability);
  return <>{allowed ? children : fallback}</>;
}
