// Server Actions for /setup. Invoked by the Add Staff dialog (client
// component). Server-side: detect contact channel, normalize, call
// create_shop_invite, surface structured errors for friendly toasts.

"use server";

import { revalidatePath } from "next/cache";
import { defaultCountryCode } from "shared";
import { createSupabaseServerClient } from "@/lib/supabase/server";

// ---------------------------------------------------------------
// Update shop settings (owner-only)
// ---------------------------------------------------------------

export type UpdateShopResult =
  | { ok: true }
  | { ok: false; code: "empty" | "permission" | "generic"; message?: string };

export async function updateShopSettingsAction(input: {
  shopId: string;
  name: string;
  currencyCode: string;
  defaultLanguageCode: string;
}): Promise<UpdateShopResult> {
  const name = input.name.trim();
  if (name.length === 0) return { ok: false, code: "empty" };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("update_shop_settings", {
    p_shop_id: input.shopId,
    p_settings: {
      name,
      currency_code: input.currencyCode,
      default_language_code: input.defaultLanguageCode,
    },
  });
  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("owner") || msg.includes("not allowed")) {
      return { ok: false, code: "permission" };
    }
    console.error("[setup-shop] update_shop_settings failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }
  revalidatePath("/setup");
  // Shop name + currency drive every other page's chrome; nuke the
  // cache broadly so the change shows up everywhere on the next nav.
  revalidatePath("/", "layout");
  return { ok: true };
}

export type UpdateProfileResult =
  | { ok: true }
  | { ok: false; code: "empty" | "generic"; message?: string };

export async function updateMyProfileAction(input: {
  displayName: string;
}): Promise<UpdateProfileResult> {
  const name = input.displayName.trim();
  if (name.length === 0) return { ok: false, code: "empty" };

  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, code: "generic" };

  const { error } = await supabase
    .from("user_profile")
    .upsert(
      { user_id: user.id, display_name: name },
      { onConflict: "user_id" },
    );
  if (error) {
    console.error("[setup-profile] upsert failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }
  revalidatePath("/setup");
  revalidatePath("/audit");
  return { ok: true };
}

export type AddStaffResult =
  | { ok: true; displayLabel: string }
  | {
      ok: false;
      code:
        | "missing_contact"
        | "invalid_phone"
        | "invalid_email"
        | "permission"
        | "conflict"
        | "generic";
      message?: string;
    };

// Mirrors the mobile + shared E.164 normalizer but kept here to avoid
// dragging the whole web/shared client surface into a server-only file.
// Accepts: leading "+", "00", or bare local-number → defaults to +252.
function normalizePhone(raw: string): string | null {
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

function normalizeEmail(value: string): string | null {
  const email = value.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null;
  return email;
}

export async function addStaffAction(input: {
  shopId: string;
  phoneRaw: string;
  emailRaw: string;
  roleCode: "cashier" | "owner";
  displayName?: string;
}): Promise<AddStaffResult> {
  const phoneRaw = input.phoneRaw.trim();
  const emailRaw = input.emailRaw.trim();

  if (phoneRaw === "" && emailRaw === "") {
    return { ok: false, code: "missing_contact" };
  }

  let phone: string | null = null;
  if (phoneRaw !== "") {
    phone = normalizePhone(phoneRaw);
    if (!phone) return { ok: false, code: "invalid_phone" };
  }

  let email: string | null = null;
  if (emailRaw !== "") {
    email = normalizeEmail(emailRaw);
    if (!email) return { ok: false, code: "invalid_email" };
  }

  const displayName = input.displayName?.trim() ?? "";

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_shop_invite", {
    p_shop_id: input.shopId,
    p_phone: phone,
    p_email: email,
    p_role_code: input.roleCode,
    p_display_name: displayName.length > 0 ? displayName : null,
  });

  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("not allowed")) {
      return { ok: false, code: "permission" };
    }
    if (
      msg.includes("different pending invites") ||
      msg.includes("already")
    ) {
      return { ok: false, code: "conflict" };
    }
    console.error("[setup-staff] create_shop_invite failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }

  revalidatePath("/setup");
  const displayLabel =
    displayName || phone || email || "";
  return { ok: true, displayLabel };
}
