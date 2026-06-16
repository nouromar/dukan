// Inline-editable product detail header. Wraps the InlineEdit
// primitives + shop-context capability check + Server Actions for
// each editable field. Replaces the modal EditProductDialog with
// always-visible click-to-edit fields:
//
//   Display name (h1)     → InlineEditText  → setProductNameAction
//   Category (chip)       → InlineEditSelect → setProductCategoryAction
//   Active toggle (chip)  → InlineEditToggle → setProductActiveAction

"use client";

import { useTranslations } from "next-intl";
import { useLocale } from "next-intl";
import { toast } from "sonner";
import {
  InlineEditText,
  InlineEditSelect,
  InlineEditToggle,
} from "@/components/shared/inline-edit";
import { useShopContext } from "@/lib/shop-context";
import { cn } from "@/lib/utils";
import {
  setProductNameAction,
  setProductCategoryAction,
  setProductActiveAction,
} from "@/app/(dashboard)/inventory/[shopItemId]/actions";

export type DetailCategoryOption = { id: string; name: string };

export function ProductDetailHeader({
  shopId,
  shopItemId,
  initialName,
  initialCategoryId,
  initialCategoryName,
  initialIsActive,
  categories,
}: {
  shopId: string;
  shopItemId: string;
  initialName: string;
  initialCategoryId: string | null;
  initialCategoryName: string | null;
  initialIsActive: boolean;
  categories: DetailCategoryOption[];
}) {
  const t = useTranslations("productDetail");
  const locale = useLocale();
  const { capabilities } = useShopContext();
  const canEdit = capabilities.has("inventory.product.edit");

  return (
    <header className="space-y-3">
      <h1
        className={cn(
          "text-3xl font-semibold tracking-tight",
          !initialIsActive && "text-muted-foreground line-through",
        )}
      >
        <InlineEditText
          value={initialName}
          display={initialName}
          readOnly={!canEdit}
          maxLength={200}
          className="text-3xl font-semibold tracking-tight"
          onSave={async (next) => {
            const r = await setProductNameAction({
              shopId,
              shopItemId,
              newName: next,
              languageCode: locale,
            });
            if (!r.ok) {
              toast.error(
                r.code === "permission"
                  ? t("editDialog.errorPermission")
                  : t("editDialog.errorGeneric"),
              );
              return { ok: false };
            }
            return { ok: true };
          }}
        />
      </h1>
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <InlineEditSelect
          value={initialCategoryId ?? ""}
          display={
            <span className="rounded-md bg-muted px-2 py-1 text-xs font-medium text-muted-foreground">
              {initialCategoryName ?? t("editDialog.categoryNone")}
            </span>
          }
          options={[
            { value: "", label: t("editDialog.categoryNone") },
            ...categories.map((c) => ({ value: c.id, label: c.name })),
          ]}
          noPencil
          readOnly={!canEdit}
          onSave={async (next) => {
            const r = await setProductCategoryAction({
              shopId,
              shopItemId,
              categoryId: next === "" ? null : next,
            });
            if (!r.ok) {
              toast.error(
                r.code === "permission"
                  ? t("editDialog.errorPermission")
                  : t("editDialog.errorGeneric"),
              );
              return { ok: false };
            }
            return { ok: true };
          }}
        />
        <InlineEditToggle
          value={initialIsActive}
          labels={[t("inactive"), t("editDialog.activeLabel")]}
          readOnly={!canEdit}
          onSave={async (next) => {
            const r = await setProductActiveAction({
              shopId,
              shopItemId,
              isActive: next,
            });
            if (!r.ok) {
              toast.error(
                r.code === "permission"
                  ? t("editDialog.errorPermission")
                  : t("editDialog.errorGeneric"),
              );
              return { ok: false };
            }
            return { ok: true };
          }}
        />
      </div>
    </header>
  );
}
