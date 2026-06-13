// Shared empty / error / loading states for tables and lists. Kept in
// data-table/ because that's where they're most often used, but
// they're plain components — feel free to drop them in any list view
// (audit feed, dashboard cards, etc.) when nothing has loaded yet.

import { AlertCircle, Inbox } from "lucide-react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

export function EmptyState({
  title,
  description,
  action,
  icon: Icon = Inbox,
}: {
  /** Override the default i18n title for context-specific wording. */
  title?: string;
  description?: string;
  action?: React.ReactNode;
  icon?: React.ComponentType<{ className?: string }>;
}) {
  const t = useTranslations("table.empty");
  return (
    <div className="flex flex-col items-center justify-center rounded-lg border border-dashed border-border bg-muted/20 px-6 py-16 text-center">
      <Icon className="mb-3 size-8 text-muted-foreground" aria-hidden />
      <h3 className="text-base font-medium">{title ?? t("title")}</h3>
      <p className="mt-1 max-w-sm text-sm text-muted-foreground">
        {description ?? t("description")}
      </p>
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}

export function ErrorState({
  title,
  description,
  onRetry,
}: {
  title?: string;
  description?: string;
  onRetry?: () => void;
}) {
  const t = useTranslations("table.error");
  return (
    <div className="flex flex-col items-center justify-center rounded-lg border border-dashed border-destructive/30 bg-destructive/5 px-6 py-16 text-center">
      <AlertCircle
        className="mb-3 size-8 text-destructive"
        aria-hidden
      />
      <h3 className="text-base font-medium text-destructive">
        {title ?? t("title")}
      </h3>
      <p className="mt-1 max-w-sm text-sm text-muted-foreground">
        {description ?? t("description")}
      </p>
      {onRetry ? (
        <Button
          variant="outline"
          size="sm"
          className="mt-4"
          onClick={onRetry}
        >
          {t("retry")}
        </Button>
      ) : null}
    </div>
  );
}

/**
 * Skeleton table — same row height + column count as the real table so
 * the layout doesn't shift when data arrives. Pass `rows` and `columns`
 * to match the eventual table dimensions.
 */
export function LoadingTable({
  rows = 8,
  columns = 4,
}: {
  rows?: number;
  columns?: number;
}) {
  return (
    <div
      className="overflow-hidden rounded-lg border"
      role="status"
      aria-busy="true"
    >
      <div className="border-b bg-muted/30 px-4 py-3">
        <div className="flex gap-4">
          {Array.from({ length: columns }).map((_, i) => (
            <Skeleton key={i} className="h-4 flex-1" />
          ))}
        </div>
      </div>
      <div className="divide-y">
        {Array.from({ length: rows }).map((_, r) => (
          <div key={r} className="flex gap-4 px-4 py-3">
            {Array.from({ length: columns }).map((_, c) => (
              <Skeleton key={c} className="h-4 flex-1" />
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
