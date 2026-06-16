// Server Actions for the party detail page. Uses the existing
// update_party RPC (from 0051_audit_log_instrument_mvp.sql) which
// audit-logs people.party.edit with before/after state.

"use server";

import { revalidatePath } from "next/cache";
import { defaultCountryCode } from "shared";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type UpdatePartyResult =
  | { ok: true }
  | {
      ok: false;
      code: "missing_name" | "invalid_phone" | "permission" | "generic";
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

export async function updatePartyAction(input: {
  shopId: string;
  partyId: string;
  name: string;
  phoneRaw: string;
}): Promise<UpdatePartyResult> {
  const name = input.name.trim();
  if (name.length === 0) return { ok: false, code: "missing_name" };

  // Empty phone = clear. Non-empty = must normalize cleanly.
  let phone: string | null = null;
  if (input.phoneRaw.trim() !== "") {
    phone = normalizePhone(input.phoneRaw);
    if (!phone) return { ok: false, code: "invalid_phone" };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("update_party", {
    p_shop_id: input.shopId,
    p_party_id: input.partyId,
    p_name: name,
    p_phone: phone,
  });
  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("not allowed")) {
      return { ok: false, code: "permission" };
    }
    console.error("[party-detail] update_party failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }
  revalidatePath(`/people/${input.partyId}`);
  revalidatePath("/people");
  revalidatePath("/aging");
  return { ok: true };
}
