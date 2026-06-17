// Server Action for the Record Receive form. Wraps post_receive RPC
// with validation + structured error codes the client can render as
// friendly toasts. The RPC handles posting + stock movement + cost
// recalc + supplier balance + audit log.

"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type RecordReceiveResult =
  | { ok: true; txnId: string }
  | {
      ok: false;
      code: "validation" | "permission" | "supplier" | "generic";
      message?: string;
    };

export type ReceiveLineInput =
  | {
      shopItemUnitId: string;
      quantity: number;
      unitCost: number;
    }
  | {
      shopItemUnitId: string;
      quantity: number;
      lineTotal: number;
    };

export async function postReceiveAction(input: {
  shopId: string;
  partyId: string;
  occurredAt: string;
  paymentMethod: "cash" | "credit";
  lines: ReceiveLineInput[];
  notes: string | null;
}): Promise<RecordReceiveResult> {
  if (!input.partyId) {
    return { ok: false, code: "validation", message: "supplier required" };
  }
  if (input.lines.length === 0) {
    return { ok: false, code: "validation", message: "at least one line" };
  }
  for (const [i, l] of input.lines.entries()) {
    if (!l.shopItemUnitId) {
      return {
        ok: false,
        code: "validation",
        message: `line ${i + 1}: missing packaging`,
      };
    }
    if (!Number.isFinite(l.quantity) || l.quantity <= 0) {
      return {
        ok: false,
        code: "validation",
        message: `line ${i + 1}: quantity must be > 0`,
      };
    }
    const cost = "unitCost" in l ? l.unitCost : l.lineTotal;
    if (!Number.isFinite(cost) || cost < 0) {
      return {
        ok: false,
        code: "validation",
        message: `line ${i + 1}: cost must be ≥ 0`,
      };
    }
  }

  // Mirror the RPC's grand-total math so paid_amount is correct for
  // the cash case without a round-trip. The RPC recomputes from the
  // same numbers — any mismatch surfaces as an RPC error rather than
  // a silent over/underpayment.
  const grandTotal = input.lines.reduce((sum, l) => {
    if ("unitCost" in l) return sum + l.quantity * l.unitCost;
    return sum + l.lineTotal;
  }, 0);

  const jsonLines = input.lines.map((l) =>
    "unitCost" in l
      ? {
          shop_item_unit_id: l.shopItemUnitId,
          quantity: l.quantity,
          unit_cost: l.unitCost,
        }
      : {
          shop_item_unit_id: l.shopItemUnitId,
          quantity: l.quantity,
          line_total: l.lineTotal,
        },
  );
  const paidAmount = input.paymentMethod === "cash" ? grandTotal : 0;
  const paymentMethodCode = input.paymentMethod === "cash" ? "cash" : null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("post_receive", {
    p_shop_id: input.shopId,
    p_party_id: input.partyId,
    p_lines: jsonLines,
    p_paid_amount: paidAmount,
    p_payment_method_code: paymentMethodCode,
    p_occurred_at: input.occurredAt,
    p_notes: input.notes,
  });

  if (error) {
    const msg = error.message?.toLowerCase() ?? "";
    if (msg.includes("not allowed") || msg.includes("permission")) {
      return { ok: false, code: "permission" };
    }
    if (msg.includes("supplier") || msg.includes("party")) {
      return { ok: false, code: "supplier", message: error.message };
    }
    console.error("[record-receive] post_receive failed:", error);
    return { ok: false, code: "generic", message: error.message };
  }

  revalidatePath("/receives");
  revalidatePath("/inventory");
  revalidatePath("/people");
  return { ok: true, txnId: (data as string) ?? "" };
}
