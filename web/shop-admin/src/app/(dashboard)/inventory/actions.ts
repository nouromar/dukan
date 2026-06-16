// Server Actions for /inventory. Three actions live here today:
//   - addProductAction      (this commit)
//   - bulkSetPriceAction    (from #289)
//   - bulkSetThresholdAction (from #289)

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

// ---------------------------------------------------------------
// Add product
// ---------------------------------------------------------------

export type AddProductResult =
  | { ok: true; shopItemId: string; name: string }
  | {
      ok: false;
      code:
        | "missing_name"
        | "missing_base_unit"
        | "permission"
        | "duplicate"
        | "generic";
      message?: string;
    };

export async function addProductAction(input: {
  shopId: string;
  name: string;
  baseUnitCode: string;
  categoryId: string | null;
  salePrice: number | null;
  /** Locale stored alongside the new item's display alias. */
  languageCode: string;
}): Promise<AddProductResult> {
  const name = input.name.trim();
  if (name.length === 0) return { ok: false, code: "missing_name" };
  if (!input.baseUnitCode) return { ok: false, code: "missing_base_unit" };
  if (input.salePrice !== null && (Number.isNaN(input.salePrice) || input.salePrice < 0)) {
    return { ok: false, code: "generic", message: "Invalid sale price" };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("create_shop_item", {
    p_shop_id: input.shopId,
    p_name: name,
    p_language_code: input.languageCode,
    p_base_unit_code: input.baseUnitCode,
    p_sale_price: input.salePrice,
    p_category_id: input.categoryId,
    // Sold packaging defaults to base unit — owner can add extra
    // pack sizes later via mobile or a future portal editor.
    p_sold_unit_code: null,
    p_sold_conversion: null,
    p_default_side: "sale",
  });

  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("not allowed")) {
      return { ok: false, code: "permission" };
    }
    if (
      msg.includes("already") ||
      msg.includes("duplicate") ||
      msg.includes("unique")
    ) {
      return { ok: false, code: "duplicate" };
    }
    console.error("[inventory] create_shop_item failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }

  const row = (data as Array<{ shop_item_id: string }> | null)?.[0];
  revalidatePath("/inventory");
  return {
    ok: true,
    shopItemId: row?.shop_item_id ?? "",
    name,
  };
}

// ---------------------------------------------------------------
// Bulk edits (#289)
// ---------------------------------------------------------------

export type BulkResult =
  | { ok: true; count: number }
  | { ok: false; code: "permission" | "validation" | "generic"; message?: string };

function classifyBulkError(message: string): "permission" | "validation" | "generic" {
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
    return {
      ok: false,
      code: classifyBulkError(error.message ?? ""),
      message: error.message,
    };
  }
  revalidatePath("/inventory");
  return { ok: true, count: Number(data ?? 0) };
}

export async function bulkSetThresholdAction(input: {
  shopId: string;
  shopItemIds: string[];
  /** null = clear the threshold. */
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
    return {
      ok: false,
      code: classifyBulkError(error.message ?? ""),
      message: error.message,
    };
  }
  revalidatePath("/inventory");
  return { ok: true, count: Number(data ?? 0) };
}
