// Server Action for inline price edits on the product detail page.
// Calls the single-unit set_shop_item_unit_sale_price RPC (which
// runs on auth_can_post_shop, so cashiers can use it too). Bulk
// updates go through bulk_set_default_sale_price (#289) instead.

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

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
// Inline-edit single fields (used by the redesigned product detail
// page). Each takes an opaque diff, calls the existing single-field
// RPC, and revalidates the detail + list paths.
// ---------------------------------------------------------------

export type FieldUpdateResult =
  | { ok: true }
  | { ok: false; code: "permission" | "generic"; message?: string };

function classifyFieldError(message: string): FieldUpdateResult {
  const m = message.toLowerCase();
  if (m.includes("not allowed") || m.includes("owner")) {
    return { ok: false, code: "permission", message };
  }
  return { ok: false, code: "generic", message };
}

/**
 * Adds a display alias (effectively renames the product).
 * Old display alias stays as a non-display alias for OCR/search reuse.
 */
export async function setProductNameAction(input: {
  shopId: string;
  shopItemId: string;
  newName: string;
  languageCode: string;
}): Promise<FieldUpdateResult> {
  if (input.newName.trim().length === 0) {
    return { ok: false, code: "generic", message: "empty name" };
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("add_shop_item_alias", {
    p_shop_id: input.shopId,
    p_shop_item_id: input.shopItemId,
    p_alias_text: input.newName.trim(),
    p_language_code: input.languageCode,
    p_is_display: true,
    p_source: "manual",
  });
  if (error) return classifyFieldError(error.message ?? "");
  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  return { ok: true };
}

export async function setProductCategoryAction(input: {
  shopId: string;
  shopItemId: string;
  categoryId: string | null;
}): Promise<FieldUpdateResult> {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("set_shop_item_category", {
    p_shop_id: input.shopId,
    p_shop_item_id: input.shopItemId,
    p_category_id: input.categoryId,
  });
  if (error) return classifyFieldError(error.message ?? "");
  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  return { ok: true };
}

export async function setProductThresholdAction(input: {
  shopId: string;
  shopItemId: string;
  threshold: number | null;
}): Promise<FieldUpdateResult> {
  if (input.threshold !== null && (Number.isNaN(input.threshold) || input.threshold < 0)) {
    return { ok: false, code: "generic", message: "invalid threshold" };
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("set_shop_item_reorder_threshold", {
    p_shop_id: input.shopId,
    p_shop_item_id: input.shopItemId,
    p_reorder_threshold: input.threshold,
  });
  if (error) return classifyFieldError(error.message ?? "");
  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  return { ok: true };
}

export async function setProductActiveAction(input: {
  shopId: string;
  shopItemId: string;
  isActive: boolean;
}): Promise<FieldUpdateResult> {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("set_shop_item_active", {
    p_shop_id: input.shopId,
    p_shop_item_id: input.shopItemId,
    p_is_active: input.isActive,
  });
  if (error) return classifyFieldError(error.message ?? "");
  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  return { ok: true };
}

// ---------------------------------------------------------------
// Packaging — add + deactivate
// ---------------------------------------------------------------

export type AddPackagingResult =
  | { ok: true; shopItemUnitId: string }
  | {
      ok: false;
      code: "validation" | "permission" | "duplicate" | "generic";
      message?: string;
    };

/**
 * Adds a new (non-base) packaging row to an existing shop_item.
 * conversion_to_base must be > 0 and != 1 (a conversion of 1 would
 * collide with the existing base-unit row).
 */
export async function addPackagingAction(input: {
  shopId: string;
  shopItemId: string;
  unitCode: string;
  conversionToBase: number;
  salePrice: number | null;
}): Promise<AddPackagingResult> {
  if (!input.unitCode) {
    return { ok: false, code: "validation", message: "unit_code required" };
  }
  if (
    !Number.isFinite(input.conversionToBase) ||
    input.conversionToBase <= 0
  ) {
    return { ok: false, code: "validation", message: "conversion must be > 0" };
  }
  if (input.salePrice !== null && (Number.isNaN(input.salePrice) || input.salePrice < 0)) {
    return { ok: false, code: "validation", message: "invalid sale price" };
  }
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("create_shop_item_unit", {
    p_shop_id: input.shopId,
    p_shop_item_id: input.shopItemId,
    p_unit_code: input.unitCode,
    p_conversion_to_base: input.conversionToBase,
    p_sale_price: input.salePrice,
  });
  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("not allowed")) {
      return { ok: false, code: "permission" };
    }
    if (msg.includes("unique") || msg.includes("already") || msg.includes("conflict")) {
      return { ok: false, code: "duplicate" };
    }
    console.error("[inventory] create_shop_item_unit failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }
  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  return { ok: true, shopItemUnitId: (data as string) ?? "" };
}

export type RemovePackagingResult =
  | { ok: true; action: "removed" | "disabled" }
  | {
      ok: false;
      code: "base_unit" | "permission" | "generic";
      message?: string;
    };

/**
 * Removes a packaging when it has never been sold or received, otherwise
 * soft-disables it so the historical transaction lines keep a valid FK.
 * The server picks; the caller learns the outcome via `action`.
 */
export async function removePackagingAction(input: {
  shopId: string;
  shopItemId: string;
  shopItemUnitId: string;
}): Promise<RemovePackagingResult> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(
    "remove_or_disable_shop_item_unit",
    {
      p_shop_id: input.shopId,
      p_shop_item_unit_id: input.shopItemUnitId,
    },
  );
  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("base")) {
      return { ok: false, code: "base_unit" };
    }
    if (msg.includes("not allowed")) {
      return { ok: false, code: "permission" };
    }
    console.error("[inventory] remove_or_disable_shop_item_unit failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }
  revalidatePath(`/inventory/${input.shopItemId}`);
  revalidatePath("/inventory");
  const action = (data === "removed" ? "removed" : "disabled") as
    | "removed"
    | "disabled";
  return { ok: true, action };
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
