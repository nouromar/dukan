// Inline-editable sale-price cell. Read-only formatted money when
// not in edit mode (or when canEdit is false). Click → text input →
// auto-save on blur or Enter. Optimistic update via useTransition;
// toast on error and revert.

"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { formatMoney } from "shared";
import { Input } from "@/components/ui/input";
import { setUnitPriceAction } from "@/app/(dashboard)/inventory/[shopItemId]/actions";

export function PriceEditCell({
  shopId,
  shopItemId,
  shopItemUnitId,
  initialPrice,
  currencyCode,
  locale,
  canEdit,
}: {
  shopId: string;
  shopItemId: string;
  shopItemUnitId: string;
  initialPrice: number | null;
  currencyCode: string;
  locale: string;
  canEdit: boolean;
}) {
  const t = useTranslations("productDetail.packaging");
  const router = useRouter();
  const [value, setValue] = useState<string>(
    initialPrice === null ? "" : initialPrice.toString(),
  );
  const [editing, setEditing] = useState(false);
  const [pending, startTransition] = useTransition();
  const inputRef = useRef<HTMLInputElement>(null);

  const display =
    initialPrice === null
      ? "—"
      : formatMoney(initialPrice, currencyCode, locale);

  function commit() {
    const raw = value.trim();
    const next = raw === "" ? null : Number(raw);
    const initial = initialPrice;
    // No-op if unchanged.
    if (next === initial) {
      setEditing(false);
      return;
    }
    if (next !== null && (Number.isNaN(next) || next < 0)) {
      toast.error(t("priceError"));
      setValue(initial === null ? "" : initial.toString());
      setEditing(false);
      return;
    }
    startTransition(async () => {
      const result = await setUnitPriceAction({
        shopId,
        shopItemId,
        shopItemUnitId,
        price: next,
      });
      if (result.ok) {
        toast.success(t("priceSaved"));
        setEditing(false);
        router.refresh();
      } else {
        toast.error(t("priceError"));
        setValue(initial === null ? "" : initial.toString());
        setEditing(false);
      }
    });
  }

  if (!canEdit) {
    return (
      <span
        className={
          initialPrice === null
            ? "text-muted-foreground tabular-nums"
            : "font-medium tabular-nums"
        }
      >
        {display}
      </span>
    );
  }

  if (!editing) {
    return (
      <button
        type="button"
        onClick={() => {
          setEditing(true);
          setTimeout(() => inputRef.current?.select(), 0);
        }}
        className={
          initialPrice === null
            ? "rounded px-2 py-1 text-sm text-muted-foreground tabular-nums hover:bg-muted"
            : "rounded px-2 py-1 font-medium tabular-nums hover:bg-muted"
        }
        title="Click to edit"
      >
        {display}
      </button>
    );
  }

  return (
    <Input
      ref={inputRef}
      type="number"
      inputMode="decimal"
      step="any"
      min={0}
      value={value}
      onChange={(e) => setValue(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          commit();
        } else if (e.key === "Escape") {
          setValue(initialPrice === null ? "" : initialPrice.toString());
          setEditing(false);
        }
      }}
      disabled={pending}
      className="ml-auto h-8 max-w-[8rem] text-right"
      autoFocus
    />
  );
}
