// Server Actions for bulk inventory operations (#289). Each one
// invokes a bulk RPC, surfaces structured errors for friendly toasts,
// and revalidates /inventory so the table reflects the new state.

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type BulkResult =
  | { ok: true; count: number }
  | { ok: false; code: "permission" | "validation" | "generic"; message?: string };

function classifyError(message: string): "permission" | "validation" | "generic" {
  const m = message.toLowerCase();
  if (m.includes("not allowed")) return "permission";
  if (
    m.includes("cannot be negative") ||
    m.includes("required") ||
    m.includes("invalid")
  ) {
    return "validation";
  }
  return "generic";
}

export async function bulkSetPriceAction(input: {
  shopId: string;
  shopItemIds: string[];
  price: number;
}): Promise<BulkResult> {
  if (input.shopItemIds.length === 0) {
    return { ok: false, code: "validation" };
  }
  if (input.price < 0 || Number.isNaN(input.price)) {
    return { ok: false, code: "validation" };
  }
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("bulk_set_default_sale_price", {
    p_shop_id: input.shopId,
    p_shop_item_ids: input.shopItemIds,
    p_price: input.price,
  });
  if (error) {
    console.error("[inventory] bulk_set_default_sale_price failed:", error);
    return { ok: false, code: classifyError(error.message ?? ""), message: error.message };
  }
  revalidatePath("/inventory");
  return { ok: true, count: Number(data ?? 0) };
}

export async function bulkSetThresholdAction(input: {
  shopId: string;
  shopItemIds: string[];
  /** null = clear the threshold (UI surfaces this as an empty field). */
  threshold: number | null;
}): Promise<BulkResult> {
  if (input.shopItemIds.length === 0) {
    return { ok: false, code: "validation" };
  }
  if (input.threshold !== null && (input.threshold < 0 || Number.isNaN(input.threshold))) {
    return { ok: false, code: "validation" };
  }
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("bulk_set_reorder_threshold", {
    p_shop_id: input.shopId,
    p_shop_item_ids: input.shopItemIds,
    p_threshold: input.threshold,
  });
  if (error) {
    console.error("[inventory] bulk_set_reorder_threshold failed:", error);
    return { ok: false, code: classifyError(error.message ?? ""), message: error.message };
  }
  revalidatePath("/inventory");
  return { ok: true, count: Number(data ?? 0) };
}
