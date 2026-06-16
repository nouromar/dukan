// Per-row remove action on a packaging row. Calls
// remove_or_disable_shop_item_unit which decides server-side:
//   * never sold/received → hard-delete
//   * referenced by history → soft-disable (history stays intact)
// The toast reports which path the server took.

"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { removePackagingAction } from "@/app/(dashboard)/inventory/[shopItemId]/actions";

export function RemovePackagingButton({
  shopId,
  shopItemId,
  shopItemUnitId,
}: {
  shopId: string;
  shopItemId: string;
  shopItemUnitId: string;
}) {
  const t = useTranslations("productDetail.packaging");
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function handleClick() {
    startTransition(async () => {
      const result = await removePackagingAction({
        shopId,
        shopItemId,
        shopItemUnitId,
      });
      if (result.ok) {
        toast.success(
          result.action === "removed"
            ? t("removeSuccessRemoved")
            : t("removeSuccessDisabled"),
        );
        router.refresh();
        return;
      }
      const key = (
        {
          base_unit: "removeErrorBase",
          permission: "removeErrorPermission",
          generic: "removeErrorGeneric",
        } as const
      )[result.code];
      toast.error(t(key));
    });
  }

  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={handleClick}
      disabled={pending}
      className="h-7 gap-1 px-2 text-muted-foreground hover:text-destructive"
      title={t("removeTooltip")}
    >
      <X className="size-3.5" aria-hidden />
      <span className="text-xs">{t("removeButton")}</span>
    </Button>
  );
}
