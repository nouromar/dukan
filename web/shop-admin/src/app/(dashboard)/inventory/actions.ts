// Server Actions for /inventory. Two actions live here today:
//   - addProductAction
//   - bulkSetPriceAction
//
// (Reorder-threshold bulk edit was removed in #334 — v1 doesn't
// support per-item reorder thresholds. The bulk_set_reorder_threshold
// RPC + shop_item.reorder_threshold column remain in the database for
// forward-compat; reintroducing the feature only needs restoring UI
// and the wrapper action.)

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { parseCsv } from "@/lib/csv-parse";

// ---------------------------------------------------------------
// CSV import (#303)
// ---------------------------------------------------------------

export type ImportProductsResult =
  | {
      ok: true;
      created: number;
      skipped: number;
      skippedReasons: Array<{ row: number; reason: string }>;
    }
  | { ok: false; code: "no_file" | "permission" | "generic"; message?: string };

export async function importProductsAction(
  formData: FormData,
): Promise<ImportProductsResult> {
  const shopId = formData.get("shopId");
  const file = formData.get("file");
  const languageCode = (formData.get("languageCode") as string) ?? "en";
  if (typeof shopId !== "string" || !shopId) {
    return { ok: false, code: "generic", message: "missing shopId" };
  }
  if (!(file instanceof File) || file.size === 0) {
    return { ok: false, code: "no_file" };
  }

  const text = await file.text();
  const rows = parseCsv(text);
  if (rows.length === 0) {
    return { ok: true, created: 0, skipped: 0, skippedReasons: [] };
  }

  // Detect header by looking for "name" in the first cell.
  const firstCells = rows[0].map((c) => c.trim().toLowerCase());
  const headerLikely = firstCells[0] === "name";
  const dataRows = headerLikely ? rows.slice(1) : rows;

  const supabase = await createSupabaseServerClient();

  // Pre-fetch reference lookups so the per-row loop doesn't roundtrip.
  const [unitsRes, categoriesRes] = await Promise.all([
    supabase.from("unit").select("code"),
    supabase.from("category").select("id, code"),
  ]);
  const validUnitCodes = new Set(
    ((unitsRes.data ?? []) as Array<{ code: string }>).map((u) => u.code),
  );
  const categoryIdByCode = new Map(
    ((categoriesRes.data ?? []) as Array<{ id: string; code: string }>).map(
      (c) => [c.code, c.id],
    ),
  );

  let created = 0;
  const skipped: Array<{ row: number; reason: string }> = [];

  for (let i = 0; i < dataRows.length; i++) {
    const cells = dataRows[i];
    const rowNum = headerLikely ? i + 2 : i + 1;
    const name = (cells[0] ?? "").trim();
    const baseUnit = (cells[1] ?? "").trim().toLowerCase();
    const categoryCode = (cells[2] ?? "").trim().toLowerCase();
    const rawPrice = (cells[3] ?? "").trim();

    if (name === "") {
      skipped.push({ row: rowNum, reason: "missing name" });
      continue;
    }
    if (!validUnitCodes.has(baseUnit)) {
      skipped.push({
        row: rowNum,
        reason: `unknown base_unit '${baseUnit}'`,
      });
      continue;
    }
    let categoryId: string | null = null;
    if (categoryCode !== "") {
      const found = categoryIdByCode.get(categoryCode);
      if (!found) {
        skipped.push({
          row: rowNum,
          reason: `unknown category '${categoryCode}'`,
        });
        continue;
      }
      categoryId = found;
    }
    let salePrice: number | null = null;
    if (rawPrice !== "") {
      const n = Number(rawPrice);
      if (Number.isNaN(n) || n < 0) {
        skipped.push({ row: rowNum, reason: "invalid sale_price" });
        continue;
      }
      salePrice = n;
    }

    const { error } = await supabase.rpc("create_shop_item", {
      p_shop_id: shopId,
      p_name: name,
      p_language_code: languageCode,
      p_base_unit_code: baseUnit,
      p_sale_price: salePrice,
      p_category_id: categoryId,
      p_sold_unit_code: null,
      p_sold_conversion: null,
      p_default_side: "sale",
    });
    if (error) {
      const msg = error.message?.toLowerCase() ?? "";
      if (msg.includes("not allowed")) {
        return { ok: false, code: "permission" };
      }
      skipped.push({ row: rowNum, reason: error.message ?? "rpc failed" });
      continue;
    }
    created += 1;
  }

  revalidatePath("/inventory");
  return {
    ok: true,
    created,
    skipped: skipped.length,
    skippedReasons: skipped,
  };
}

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

