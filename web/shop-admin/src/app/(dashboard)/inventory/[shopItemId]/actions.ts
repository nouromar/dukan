// Server Action for inline price edits on the product detail page.
// Calls the single-unit set_shop_item_unit_sale_price RPC (which
// runs on auth_can_post_shop, so cashiers can use it too). Bulk
// updates go through bulk_set_default_sale_price (#289) instead.

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type SetUnitPriceResult =
  | { ok: true }
  | { ok: false; code: "validation" | "permission" | "generic"; message?: string };

export async function setUnitPriceAction(input: {
  shopId: string;
  shopItemId: string;
  shopItemUnitId: string;
  /** null = clear price; numeric = set. Negative is rejected by the RPC. */
  price: number | null;
}): Promise<SetUnitPriceResult> {
  if (input.price !== null && (Number.isNaN(input.price) || input.price < 0)) {
    return { ok: false, code: "validation" };
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("set_shop_item_unit_sale_price", {
    p_shop_id: input.shopId,
    p_shop_item_unit_id: input.shopItemUnitId,
    p_sale_price: input.price,
  });
  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("not allowed")) {
      return { ok: false, code: "permission" };
    }
    console.error("[product-detail] set price failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }
  // Revalidate so any other surface that shows the same price (the
  // inventory list, the product card, etc.) re-renders.
  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  return { ok: true };
}
