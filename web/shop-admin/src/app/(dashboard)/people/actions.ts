// Server Action for adding customers / suppliers from /people. Uses
// the existing create_party RPC (migration 0027), which audit-logs
// people.party.create and gates on auth_can_post_shop.

"use server";

import { revalidatePath } from "next/cache";
import { defaultCountryCode } from "shared";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { parseCsv } from "@/lib/csv-parse";

// ---------------------------------------------------------------
// CSV import (#302)
// ---------------------------------------------------------------

export type ImportPartiesResult =
  | {
      ok: true;
      created: number;
      skipped: number;
      skippedReasons: Array<{ row: number; reason: string }>;
    }
  | { ok: false; code: "no_file" | "permission" | "generic"; message?: string };

export async function importPartiesAction(
  formData: FormData,
): Promise<ImportPartiesResult> {
  const shopId = formData.get("shopId");
  const file = formData.get("file");
  if (typeof shopId !== "string" || !shopId) {
    return { ok: false, code: "generic", message: "missing shopId" };
  }
  if (!(file instanceof File) || file.size === 0) {
    return { ok: false, code: "no_file" };
  }

  const text = await file.text();
  const rows = parseCsv(text);
  if (rows.length === 0) {
    return {
      ok: true,
      created: 0,
      skipped: 0,
      skippedReasons: [],
    };
  }

  // Detect + skip a header row (any non-customer/supplier in column 3).
  const firstCells = rows[0].map((c) => c.trim().toLowerCase());
  const headerLikely =
    firstCells[2] !== "customer" && firstCells[2] !== "supplier";
  const dataRows = headerLikely ? rows.slice(1) : rows;

  const supabase = await createSupabaseServerClient();

  let created = 0;
  const skipped: Array<{ row: number; reason: string }> = [];

  for (let i = 0; i < dataRows.length; i++) {
    const cells = dataRows[i];
    const rowNum = (headerLikely ? i + 2 : i + 1);
    const name = (cells[0] ?? "").trim();
    const rawPhone = (cells[1] ?? "").trim();
    const typeCode = (cells[2] ?? "").trim().toLowerCase();

    if (name === "") {
      skipped.push({ row: rowNum, reason: "missing name" });
      continue;
    }
    if (typeCode !== "customer" && typeCode !== "supplier") {
      skipped.push({ row: rowNum, reason: "type must be customer or supplier" });
      continue;
    }

    let phone: string | null = null;
    if (rawPhone !== "") {
      phone = normalizePhoneForImport(rawPhone);
      if (!phone) {
        skipped.push({ row: rowNum, reason: "invalid phone" });
        continue;
      }
    }

    const { error } = await supabase.rpc("create_party", {
      p_shop_id: shopId,
      p_name: name,
      p_phone: phone,
      p_type_code: typeCode,
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

  revalidatePath("/people");
  revalidatePath("/aging");
  return {
    ok: true,
    created,
    skipped: skipped.length,
    skippedReasons: skipped,
  };
}

function normalizePhoneForImport(raw: string): string | null {
  let phone = raw.replace(/[\s\-()]/g, "");
  if (phone.startsWith("00")) {
    phone = "+" + phone.slice(2);
  } else if (phone.startsWith("0")) {
    phone = `${defaultCountryCode}${phone.slice(1)}`;
  } else if (!phone.startsWith("+")) {
    phone = `${defaultCountryCode}${phone}`;
  }
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) return null;
  return phone;
}

export type AddPartyResult =
  | { ok: true; partyId: string; name: string }
  | {
      ok: false;
      code:
        | "missing_name"
        | "invalid_phone"
        | "permission"
        | "duplicate"
        | "generic";
      message?: string;
    };

function normalizePhone(raw: string): string | null {
  if (raw.trim() === "") return null;
  let phone = raw.replace(/[\s\-()]/g, "");
  if (phone.startsWith("00")) {
    phone = "+" + phone.slice(2);
  } else if (phone.startsWith("0")) {
    phone = `${defaultCountryCode}${phone.slice(1)}`;
  } else if (!phone.startsWith("+")) {
    phone = `${defaultCountryCode}${phone}`;
  }
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) return null;
  return phone;
}

export async function addPartyAction(input: {
  shopId: string;
  name: string;
  phoneRaw: string;
  typeCode: "customer" | "supplier";
}): Promise<AddPartyResult> {
  const name = input.name.trim();
  if (name.length === 0) return { ok: false, code: "missing_name" };

  let phone: string | null = null;
  if (input.phoneRaw.trim() !== "") {
    phone = normalizePhone(input.phoneRaw);
    if (!phone) return { ok: false, code: "invalid_phone" };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("create_party", {
    p_shop_id: input.shopId,
    p_name: name,
    p_phone: phone,
    p_type_code: input.typeCode,
  });

  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("not allowed")) {
      return { ok: false, code: "permission" };
    }
    if (msg.includes("already") || msg.includes("duplicate") || msg.includes("unique")) {
      return { ok: false, code: "duplicate" };
    }
    console.error("[people] create_party failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }
  revalidatePath("/people");
  revalidatePath("/aging");
  return {
    ok: true,
    partyId: (data as string) ?? "",
    name,
  };
}
