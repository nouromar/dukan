// Per-row disable action on a packaging row. Calls
// deactivate_shop_item_unit which refuses the base packaging and
// (per backend) errors when transactions reference the unit.

"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { deactivatePackagingAction } from "@/app/(dashboard)/inventory/[shopItemId]/actions";

export function DisablePackagingButton({
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
      const result = await deactivatePackagingAction({
        shopId,
        shopItemId,
        shopItemUnitId,
      });
      if (result.ok) {
        toast.success(t("disableSuccess"));
        router.refresh();
        return;
      }
      const key = (
        {
          base_unit: "disableErrorBase",
          permission: "disableErrorPermission",
          in_use: "disableErrorInUse",
          generic: "disableErrorGeneric",
        } as const
      )[result.code];
      toast.error(t(key as "disableErrorGeneric"));
    });
  }

  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={handleClick}
      disabled={pending}
      className="h-7 gap-1 px-2 text-muted-foreground hover:text-destructive"
      title={t("disableTooltip")}
    >
      <X className="size-3.5" aria-hidden />
      <span className="text-xs">{t("disableButton")}</span>
    </Button>
  );
}
