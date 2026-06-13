// Sticky-bottom action bar that appears when one or more rows in a
// DataTable are selected. Slides in from the bottom — the entire bar
// is a single horizontal strip so it never competes with the table
// for vertical space and never causes layout shift.
//
// Per docs/shop-admin-portal.md § 7: actions here are explicitly
// limited to read/export/correction operations. No new sales/receives
// are entered from the portal.

"use client";

import { useTranslations } from "next-intl";
import { X } from "lucide-react";
import { Button, type buttonVariants } from "@/components/ui/button";
import type { VariantProps } from "class-variance-authority";

export type BulkAction = {
  /** Stable identifier for the action — used as key. */
  id: string;
  label: string;
  /** Optional icon rendered to the left of the label. */
  icon?: React.ComponentType<{ className?: string }>;
  variant?: VariantProps<typeof buttonVariants>["variant"];
  onClick: () => void;
  /** Disable the action when selection is invalid (e.g. mixed types). */
  disabled?: boolean;
};

export function BulkActionBar({
  selectedCount,
  actions,
  onClear,
}: {
  selectedCount: number;
  actions: BulkAction[];
  onClear: () => void;
}) {
  const t = useTranslations("table.selection");

  // Render nothing when no rows are selected so the bar contributes
  // zero pixels to layout while idle.
  if (selectedCount === 0) return null;

  return (
    <div
      role="region"
      aria-label="Bulk actions"
      className="sticky bottom-0 left-0 right-0 z-30 mt-4 flex items-center gap-3 rounded-lg border border-primary/20 bg-background px-4 py-2 shadow-lg"
    >
      <span className="text-sm font-medium">
        {t("count", { count: selectedCount })}
      </span>
      <Button
        type="button"
        variant="ghost"
        size="sm"
        onClick={onClear}
        aria-label={t("clear")}
        className="gap-1.5"
      >
        <X className="size-3.5" aria-hidden />
        {t("clear")}
      </Button>
      <div className="ml-auto flex items-center gap-2">
        {actions.map(({ id, label, icon: Icon, variant = "default", onClick, disabled }) => (
          <Button
            key={id}
            type="button"
            size="sm"
            variant={variant}
            onClick={onClick}
            disabled={disabled}
            className="gap-1.5"
          >
            {Icon ? <Icon className="size-4" aria-hidden /> : null}
            {label}
          </Button>
        ))}
      </div>
    </div>
  );
}
