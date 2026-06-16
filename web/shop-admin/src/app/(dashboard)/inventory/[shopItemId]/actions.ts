// Server Action for inline price edits on the product detail page.
// Calls the single-unit set_shop_item_unit_sale_price RPC (which
// runs on auth_can_post_shop, so cashiers can use it too). Bulk
// updates go through bulk_set_default_sale_price (#289) instead.

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

// ---------------------------------------------------------------
// Edit product — multi-RPC save
// ---------------------------------------------------------------

export type EditProductResult =
  | { ok: true }
  | { ok: false; code: "permission" | "generic"; message?: string };

/**
 * Calls each underlying RPC only for fields the user actually changed.
 * Non-atomic — if one of the calls fails after another succeeds, the
 * earlier change persists. That's acceptable for this v1 surface
 * because each field is independent (no integrity dependencies).
 */
export async function editProductAction(input: {
  shopId: string;
  shopItemId: string;
  /** New display alias to add (skipped when null). */
  newName: string | null;
  /** Locale for the alias (matches the user's UI locale). */
  newNameLocale: string;
  /** undefined = don't touch; null = clear category; uuid = set. */
  categoryId: string | null | undefined;
  /** undefined = don't touch; null = clear threshold; number = set. */
  threshold: number | null | undefined;
  /** undefined = don't touch; boolean = set is_active flag. */
  isActive: boolean | undefined;
}): Promise<EditProductResult> {
  const supabase = await createSupabaseServerClient();
  const errors: string[] = [];

  if (input.newName && input.newName.trim().length > 0) {
    const { error } = await supabase.rpc("add_shop_item_alias", {
      p_shop_id: input.shopId,
      p_shop_item_id: input.shopItemId,
      p_alias_text: input.newName.trim(),
      p_language_code: input.newNameLocale,
      p_is_display: true,
      p_source: "manual",
    });
    if (error) errors.push(`alias: ${error.message}`);
  }

  // Distinguish "user provided category null/blank" from "user didn't touch
  // the field". The page passes null when blank, but it's still valid to
  // call set_shop_item_category with null (clear category). For v1 we
  // skip the call when the value equals the current — the page is
  // responsible for not passing a no-op.
  if (input.categoryId !== undefined) {
    const { error } = await supabase.rpc("set_shop_item_category", {
      p_shop_id: input.shopId,
      p_shop_item_id: input.shopItemId,
      p_category_id: input.categoryId,
    });
    if (error) errors.push(`category: ${error.message}`);
  }

  if (input.threshold !== undefined) {
    const { error } = await supabase.rpc("set_shop_item_reorder_threshold", {
      p_shop_id: input.shopId,
      p_shop_item_id: input.shopItemId,
      p_reorder_threshold: input.threshold,
    });
    if (error) errors.push(`threshold: ${error.message}`);
  }

  if (input.isActive !== undefined) {
    const { error } = await supabase.rpc("set_shop_item_active", {
      p_shop_id: input.shopId,
      p_shop_item_id: input.shopItemId,
      p_is_active: input.isActive,
    });
    if (error) errors.push(`active: ${error.message}`);
  }

  if (errors.length > 0) {
    const joined = errors.join("; ");
    if (joined.toLowerCase().includes("not allowed")) {
      return { ok: false, code: "permission", message: joined };
    }
    console.error("[edit-product] failed:", joined);
    return { ok: false, code: "generic", message: joined };
  }

  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  return { ok: true };
}

// ---------------------------------------------------------------
// Stock adjustment (owner-only — single-line wrapper around the
// post_inventory_adjustment RPC)
// ---------------------------------------------------------------

export type AdjustStockResult =
  | { ok: true; adjustmentId: string }
  | {
      ok: false;
      code: "validation" | "reason_mismatch" | "permission" | "generic";
      message?: string;
    };

export async function adjustStockAction(input: {
  shopId: string;
  shopItemId: string;
  /** Positive = add, negative = remove. Zero is refused. In base units. */
  quantityDelta: number;
  reasonCode: string;
  notes: string | null;
}): Promise<AdjustStockResult> {
  if (!Number.isFinite(input.quantityDelta) || input.quantityDelta === 0) {
    return { ok: false, code: "validation" };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("post_inventory_adjustment", {
    p_shop_id: input.shopId,
    p_reason_code: input.reasonCode,
    p_lines: [
      { shop_item_id: input.shopItemId, quantity_delta: input.quantityDelta },
    ],
    p_notes: input.notes,
  });

  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("not allowed") || msg.includes("owner")) {
      return { ok: false, code: "permission" };
    }
    if (msg.includes("reason") && (msg.includes("increase") || msg.includes("decrease") || msg.includes("sign"))) {
      return { ok: false, code: "reason_mismatch" };
    }
    console.error("[inventory] post_inventory_adjustment failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }

  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  return { ok: true, adjustmentId: (data as string) ?? "" };
}

// ---------------------------------------------------------------
// Inline single-unit price edit (from #286)
// ---------------------------------------------------------------

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
