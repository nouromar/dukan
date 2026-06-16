// Client-side filters bar for /sales. Pushes changes through the
// URL (searchParams) so deep-links + the browser back/forward keep
// the filter state. The page re-renders with the new RPC args.

"use client";

import { useTransition } from "react";
import { useRouter, useSearchParams, usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export type PartyOption = { id: string; name: string };

export function SalesFilters({
  parties,
  initialFrom,
  initialTo,
  initialPartyId,
}: {
  parties: PartyOption[];
  initialFrom: string | null;
  initialTo: string | null;
  initialPartyId: string | null;
}) {
  const t = useTranslations("sales.filters");
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  function setParam(key: string, value: string | null) {
    const next = new URLSearchParams(searchParams.toString());
    if (value && value !== "") {
      next.set(key, value);
    } else {
      next.delete(key);
    }
    startTransition(() => {
      router.replace(`${pathname}?${next.toString()}`, { scroll: false });
    });
  }

  function clearAll() {
    startTransition(() => {
      router.replace(pathname, { scroll: false });
    });
  }

  const hasAnyFilter =
    initialFrom !== null || initialTo !== null || initialPartyId !== null;

  return (
    <div className="flex flex-wrap items-end gap-3 rounded-md border bg-muted/20 p-3">
      <div className="space-y-1">
        <Label htmlFor="sales-from" className="text-xs">
          {t("from")}
        </Label>
        <Input
          id="sales-from"
          type="date"
          value={initialFrom ?? ""}
          onChange={(e) => setParam("from", e.target.value || null)}
          className="h-9 w-[10rem]"
        />
      </div>
      <div className="space-y-1">
        <Label htmlFor="sales-to" className="text-xs">
          {t("to")}
        </Label>
        <Input
          id="sales-to"
          type="date"
          value={initialTo ?? ""}
          onChange={(e) => setParam("to", e.target.value || null)}
          className="h-9 w-[10rem]"
        />
      </div>
      <div className="space-y-1">
        <Label htmlFor="sales-party" className="text-xs">
          {t("party")}
        </Label>
        <select
          id="sales-party"
          value={initialPartyId ?? ""}
          onChange={(e) => setParam("party", e.target.value || null)}
          className="h-9 w-[14rem] rounded-md border border-input bg-background px-3 py-1 text-sm"
        >
          <option value="">{t("anyParty")}</option>
          {parties.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
      </div>
      {hasAnyFilter ? (
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
