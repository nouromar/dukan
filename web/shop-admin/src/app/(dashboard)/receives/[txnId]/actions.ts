// Server Action for VoidReceiveButton. Calls void_receive RPC, which
// itself enforces the owner role + 7-day window. We translate the
// known error messages into structured codes so the client can show
// friendly toasts.

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type VoidReceiveResult =
  | { ok: true }
  | {
      ok: false;
      code:
        | "not_owner"
        | "window_expired"
        | "already_voided"
        | "missing_reason"
        | "generic";
      message?: string;
    };

export async function voidReceiveAction(input: {
  shopId: string;
  txnId: string;
  reason: string;
}): Promise<VoidReceiveResult> {
  const reason = input.reason.trim();
  if (reason.length === 0) {
    return { ok: false, code: "missing_reason" };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("void_receive", {
    p_shop_id: input.shopId,
    p_txn_id: input.txnId,
    p_reason: reason,
  });

  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("only the shop owner")) {
      return { ok: false, code: "not_owner" };
    }
    if (msg.includes("void window") || msg.includes("7 days")) {
      return { ok: false, code: "window_expired" };
    }
    if (msg.includes("already") && msg.includes("void")) {
      return { ok: false, code: "already_voided" };
    }
    console.error("[void-receive] rpc failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }

  revalidatePath(`/receives/${input.txnId}`);
  revalidatePath("/receives");
  // Stock + supplier balance moved — touch inventory + people so they
  // re-fetch on next visit.
  revalidatePath("/inventory");
  revalidatePath("/people");
  return { ok: true };
}
