"use client";

import { Check, ChevronsUpDown, Store } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useShopContext } from "@/lib/shop-context";

export function ShopSwitcher() {
  const { shops, currentShop } = useShopContext();

  // Zero shops: most likely a brand-new user whose org/shop is still
  // being created on mobile. Show a quiet badge instead of an empty
  // dropdown the user can't interact with.
  if (shops.length === 0) {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Store className="size-4" aria-hidden />
        <span>No shops yet</span>
      </div>
    );
  }

  // Single shop: no switcher needed — just the name. Saves a tap.
  if (shops.length === 1) {
    return (
      <div className="flex items-center gap-2 text-sm">
        <Store
          className="size-4 text-muted-foreground"
          aria-hidden
        />
        <span className="font-medium">{currentShop?.name ?? shops[0].name}</span>
      </div>
    );
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          buttonVariants({ variant: "ghost", size: "sm" }),
          "gap-2",
        )}
      >
        <Store className="size-4" aria-hidden />
        <span className="max-w-[200px] truncate text-sm font-medium">
          {currentShop?.name ?? "Select shop"}
        </span>
        <ChevronsUpDown className="size-3 text-muted-foreground" aria-hidden />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-64">
        <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">
          Switch shop
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        {shops.map((shop) => {
          const selected = shop.id === currentShop?.id;
          return (
            <DropdownMenuItem key={shop.id}>
              <form
                action="/auth/select-shop"
                method="post"
                className="w-full"
              >
                <input type="hidden" name="shopId" value={shop.id} />
                <button
                  type="submit"
                  className="flex w-full items-center justify-between text-left"
                >
                  <span className="truncate">{shop.name}</span>
                  {selected ? (
                    <Check
                      className="size-4 text-primary"
                      aria-label="Selected"
                    />
                  ) : null}
                </button>
              </form>
            </DropdownMenuItem>
          );
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
