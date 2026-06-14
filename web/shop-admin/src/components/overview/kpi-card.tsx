// Single KPI cell used in the Overview's hero row. Visual: a card with
// a small label, a large value, and an optional one-line secondary
// (e.g. "12 sales"). Kept dumb on purpose — the page composes a row
// of these.

import type { LucideIcon } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";

export function KpiCard({
  label,
  value,
  secondary,
  icon: Icon,
}: {
  label: string;
  value: string;
  secondary?: string;
  icon?: LucideIcon;
}) {
  return (
    <Card>
      <CardContent className="space-y-1 pt-6">
        <div className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {Icon ? <Icon className="size-3.5" aria-hidden /> : null}
          {label}
        </div>
        <div className="text-2xl font-semibold tracking-tight">{value}</div>
        {secondary ? (
          <div className="text-xs text-muted-foreground">{secondary}</div>
        ) : null}
      </CardContent>
    </Card>
  );
}
