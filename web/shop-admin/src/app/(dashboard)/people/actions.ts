// Server Action for adding customers / suppliers from /people. Uses
// the existing create_party RPC (migration 0027), which audit-logs
// people.party.create and gates on auth_can_post_shop.

"use server";

import { revalidatePath } from "next/cache";
import { defaultCountryCode } from "shared";
import { createSupabaseServerClient } from "@/lib/supabase/server";

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
