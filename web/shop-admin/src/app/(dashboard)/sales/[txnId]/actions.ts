// Server Action invoked by VoidSaleButton. Lives in a separate file so
// the client component can import it without dragging server-only
// dependencies into the bundle.
//
// Capability + 7-day window enforcement happens server-side in the
// void_sale RPC; this action only translates form data into the call
// and surfaces structured errors back to the client.

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type VoidSaleResult =
  | { ok: true }
  | { ok: false; code: "not_owner" | "window_expired" | "already_voided" | "missing_reason" | "generic"; message?: string };

export async function voidSaleAction(input: {
  shopId: string;
  txnId: string;
  reason: string;
}): Promise<VoidSaleResult> {
  const reason = input.reason.trim();
  if (reason.length === 0) {
    return { ok: false, code: "missing_reason" };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("void_sale", {
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
    console.error("[void-sale] rpc failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }

  // Revalidate so the detail page + the sales list both pick up the
  // new is_voided=true state on next render.
  revalidatePath(`/sales/${input.txnId}`);
  revalidatePath("/sales");
  return { ok: true };
}
