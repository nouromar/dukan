// Audit filter bar — action + date range. URL-state-backed, same
// pattern as SalesFilters.

"use client";

import { useTransition } from "react";
import { useRouter, useSearchParams, usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export type ActionOption = { code: string; label: string };

export function AuditFilters({
  actions,
  initialAction,
  initialFrom,
  initialTo,
}: {
  actions: ActionOption[];
  initialAction: string | null;
  initialFrom: string | null;
  initialTo: string | null;
}) {
  const t = useTranslations("audit.filters");
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  function setParam(key: string, value: string | null) {
    const next = new URLSearchParams(searchParams.toString());
    if (value && value !== "") next.set(key, value);
    else next.delete(key);
    startTransition(() => {
      router.replace(`${pathname}?${next.toString()}`, { scroll: false });
    });
  }

  function clearAll() {
    startTransition(() => router.replace(pathname, { scroll: false }));
  }

  const hasAny =
    initialAction !== null || initialFrom !== null || initialTo !== null;

  return (
    <div className="flex flex-wrap items-end gap-3 rounded-md border bg-muted/20 p-3">
      <div className="space-y-1">
        <Label htmlFor="audit-action" className="text-xs">
          {t("action")}
        </Label>
        <select
          id="audit-action"
          value={initialAction ?? ""}
          onChange={(e) => setParam("action", e.target.value || null)}
          className="h-9 w-[16rem] rounded-md border border-input bg-background px-3 py-1 text-sm"
        >
          <option value="">{t("anyAction")}</option>
          {actions.map((a) => (
            <option key={a.code} value={a.code}>
              {a.label}
            </option>
          ))}
        </select>
      </div>
      <div className="space-y-1">
        <Label htmlFor="audit-from" className="text-xs">
          {t("from")}
        </Label>
        <Input
          id="audit-from"
          type="date"
          value={initialFrom ?? ""}
          onChange={(e) => setParam("from", e.target.value || null)}
          className="h-9 w-[10rem]"
        />
      </div>
      <div className="space-y-1">
        <Label htmlFor="audit-to" className="text-xs">
          {t("to")}
        </Label>
        <Input
          id="audit-to"
          type="date"
          value={initialTo ?? ""}
          onChange={(e) => setParam("to", e.target.value || null)}
          className="h-9 w-[10rem]"
        />
      </div>
      {hasAny ? (
        <Button
          variant="ghost"
          size="sm"
          onClick={clearAll}
          className="gap-1.5"
        >
          <X className="size-3.5" aria-hidden />
          {t("clear")}
        </Button>
      ) : null}
    </div>
  );
}
