// Single Route Handler for CSV export. /api/export/<module>?
//
// Modules: sales | inventory | customers | suppliers | audit | aging
// Capability gating per-module:
//   sales      → sales.export
//   inventory  → inventory.product.view (read-only export of own data)
//   customers  → people.statement.export
//   suppliers  → people.statement.export
//   audit      → audit.export
//   aging      → people.statement.export
//
// Falls back to 403 when the capability is missing. RLS still applies
// to every underlying query; the capability check is the friendlier
// gate that returns a clean 403 instead of a row-empty CSV.

import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getCurrentShop } from "@/lib/current-shop";
import { historyPageLimit, formatMoney, formatCount } from "shared";
import { toCsv, csvFilename } from "@/lib/csv";

type Module = "sales" | "inventory" | "customers" | "suppliers" | "audit" | "aging";

const CAPABILITY_FOR_MODULE: Record<Module, string> = {
  sales: "sales.export",
  inventory: "inventory.product.view",
  customers: "people.statement.export",
  suppliers: "people.statement.export",
  audit: "audit.export",
  aging: "people.statement.export",
};

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ module: string }> },
) {
  const { module } = await params;
  const m = module as Module;
  const cap = CAPABILITY_FOR_MODULE[m];
  if (!cap) {
    return new NextResponse("unknown module", { status: 404 });
  }

  const { currentShop, capabilities } = await getCurrentShop();
  if (!currentShop) {
    return new NextResponse("no shop", { status: 400 });
  }
  if (!capabilities.includes(cap)) {
    return new NextResponse("forbidden", { status: 403 });
  }

  const supabase = await createSupabaseServerClient();
  let body: string;
  try {
    switch (m) {
      case "sales":
        body = await exportSales(supabase, currentShop.id, currentShop.currency_code);
        break;
      case "inventory":
        body = await exportInventory(supabase, currentShop.id, currentShop.currency_code);
        break;
      case "customers":
        body = await exportParties(supabase, currentShop.id, "customer", currentShop.currency_code);
        break;
      case "suppliers":
        body = await exportParties(supabase, currentShop.id, "supplier", currentShop.currency_code);
        break;
      case "audit":
        body = await exportAudit(supabase, currentShop.id);
        break;
      case "aging":
        body = await exportAging(supabase, currentShop.id, currentShop.currency_code);
        break;
    }
  } catch (err) {
    console.error(`[export:${m}] failed:`, err);
    return new NextResponse("export failed", { status: 500 });
  }

  const filename = csvFilename(currentShop.name, m);
  return new NextResponse(body, {
    status: 200,
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${filename}"`,
      // Allow direct browser download even when the link is
      // opened in a new tab; no caching since data changes.
      "Cache-Control": "no-store",
    },
  });
}

// ---------------------------------------------------------------
// Per-module dump shapes.
// ---------------------------------------------------------------

type SupabaseClient = Awaited<ReturnType<typeof createSupabaseServerClient>>;

async function exportSales(
  supabase: SupabaseClient,
  shopId: string,
  currency: string,
): Promise<string> {
  const { data, error } = await supabase.rpc("list_sales", {
    p_shop_id: shopId,
    p_limit: historyPageLimit,
  });
  if (error) throw error;
  const headers = [
    "txn_id",
    "occurred_at",
    "customer_name",
    "total",
    "paid",
    "payment_method",
    "is_voided",
    "currency",
  ];
  const rows = ((data ?? []) as Array<Record<string, unknown>>).map((r) => [
    r.txn_id,
    r.occurred_at,
    r.party_name ?? "",
    formatMoney(Number(r.total_amount ?? 0), currency, "en"),
    formatMoney(Number(r.paid_amount ?? 0), currency, "en"),
    r.payment_method_code ?? "",
    r.is_voided,
    currency,
  ]);
  return toCsv(headers, rows);
}

async function exportInventory(
  supabase: SupabaseClient,
  shopId: string,
  currency: string,
): Promise<string> {
  const { data, error } = await supabase.rpc("list_shop_items", {
    p_shop_id: shopId,
    p_locale: "en",
  });
  if (error) throw error;
  const headers = [
    "shop_item_id",
    "name",
    "category",
    "base_unit",
    "current_stock",
    "default_sale_cost",
    "default_sale_price",
    "is_active",
    "currency",
  ];
  const rows = ((data ?? []) as Array<Record<string, unknown>>).map((r) => [
    r.shop_item_id,
    r.display_name,
    r.category_name ?? "",
    r.base_unit_code,
    formatCount(Number(r.current_stock ?? 0), "en"),
    r.default_sale_cost === null || r.default_sale_cost === undefined
      ? ""
      : formatMoney(Number(r.default_sale_cost), currency, "en"),
    r.default_sale_price === null
      ? ""
      : formatMoney(Number(r.default_sale_price), currency, "en"),
    r.is_active,
    currency,
  ]);
  return toCsv(headers, rows);
}

async function exportParties(
  supabase: SupabaseClient,
  shopId: string,
  kind: "customer" | "supplier",
  currency: string,
): Promise<string> {
  const [partiesRes, typesRes] = await Promise.all([
    supabase
      .from("party")
      .select("id, name, phone, receivable, payable, type_id")
      .eq("shop_id", shopId)
      .eq("is_active", true)
      .order("name", { ascending: true }),
    supabase.from("party_type").select("id, code"),
  ]);
  if (partiesRes.error) throw partiesRes.error;
  if (typesRes.error) throw typesRes.error;

  const typeById = new Map(
    ((typesRes.data ?? []) as Array<{ id: string; code: string }>).map(
      (t) => [t.id, t.code],
    ),
  );
  const headers = [
    "party_id",
    "name",
    "phone",
    kind === "customer" ? "owes_you" : "you_owe",
    "currency",
  ];
  const rows = ((partiesRes.data ?? []) as Array<Record<string, unknown>>)
    .filter((r) => typeById.get(r.type_id as string) === kind)
    .map((r) => [
      r.id,
      r.name,
      r.phone ?? "",
      formatMoney(
        Number((kind === "customer" ? r.receivable : r.payable) ?? 0),
        currency,
        "en",
      ),
      currency,
    ]);
  return toCsv(headers, rows);
}

async function exportAudit(supabase: SupabaseClient, shopId: string): Promise<string> {
  const [eventsRes, actionsRes] = await Promise.all([
    supabase
      .from("audit_log")
      .select(
        "id, occurred_at, action_code, entity_type, entity_id, source, actor_user_id",
      )
      .eq("shop_id", shopId)
      .order("occurred_at", { ascending: false })
      .limit(1000),
    supabase.from("audit_action_code").select("code, description"),
  ]);
  if (eventsRes.error) throw eventsRes.error;
  if (actionsRes.error) throw actionsRes.error;

  const descByCode = new Map(
    ((actionsRes.data ?? []) as Array<{ code: string; description: string | null }>)
      .map((r) => [r.code, r.description ?? r.code]),
  );

  const headers = [
    "id",
    "occurred_at",
    "action_code",
    "action_label",
    "entity_type",
    "entity_id",
    "actor_user_id",
    "source",
  ];
  const rows = ((eventsRes.data ?? []) as Array<Record<string, unknown>>).map(
    (r) => [
      r.id,
      r.occurred_at,
      r.action_code,
      descByCode.get(r.action_code as string) ?? r.action_code,
      r.entity_type,
      r.entity_id ?? "",
      r.actor_user_id ?? "",
      r.source,
    ],
  );
  return toCsv(headers, rows);
}

async function exportAging(
  supabase: SupabaseClient,
  shopId: string,
  currency: string,
): Promise<string> {
  // Mirrors the /aging page logic. Parties with non-zero balance,
  // joined with their latest activity timestamp computed from txn +
  // payment, bucket via days_since.
  const [partiesRes, typesRes, txnsRes, paymentsRes] = await Promise.all([
    supabase
      .from("party")
      .select("id, name, receivable, payable, type_id")
      .eq("shop_id", shopId)
      .eq("is_active", true),
    supabase.from("party_type").select("id, code"),
    supabase
      .from("txn")
      .select("party_id, occurred_at")
      .eq("shop_id", shopId)
      .not("party_id", "is", null),
    supabase
      .from("payment")
      .select("party_id, occurred_at")
      .eq("shop_id", shopId)
      .not("party_id", "is", null),
  ]);
  for (const r of [partiesRes, typesRes, txnsRes, paymentsRes]) {
    if (r.error) throw r.error;
  }

  const typeById = new Map(
    ((typesRes.data ?? []) as Array<{ id: string; code: string }>).map(
      (t) => [t.id, t.code],
    ),
  );
  const lastByParty = new Map<string, string>();
  for (const r of (txnsRes.data ?? []) as Array<{
    party_id: string;
    occurred_at: string;
  }>) {
    const prev = lastByParty.get(r.party_id);
    if (!prev || prev < r.occurred_at) lastByParty.set(r.party_id, r.occurred_at);
  }
  for (const r of (paymentsRes.data ?? []) as Array<{
    party_id: string;
    occurred_at: string;
  }>) {
    const prev = lastByParty.get(r.party_id);
    if (!prev || prev < r.occurred_at) lastByParty.set(r.party_id, r.occurred_at);
  }

  const DAY_MS = 24 * 60 * 60 * 1000;
  const now = Date.now();
  const bucketFor = (daysSince: number | null) =>
    daysSince === null
      ? "never"
      : daysSince <= 30
        ? "current"
        : daysSince <= 60
          ? "31-60"
          : daysSince <= 90
            ? "61-90"
            : "90+";

  const headers = [
    "party_id",
    "name",
    "type",
    "balance",
    "last_activity_at",
    "days_since",
    "bucket",
    "currency",
  ];
  const rows: unknown[][] = [];
  for (const p of (partiesRes.data ?? []) as Array<Record<string, unknown>>) {
    const code = typeById.get(p.type_id as string);
    if (code !== "customer" && code !== "supplier") continue;
    const balance = Number(
      (code === "customer" ? p.receivable : p.payable) ?? 0,
    );
    if (balance <= 0) continue;
    const last = lastByParty.get(p.id as string) ?? null;
    const daysSince =
      last === null ? null : Math.floor((now - new Date(last).getTime()) / DAY_MS);
    rows.push([
      p.id,
      p.name,
      code,
      formatMoney(balance, currency, "en"),
      last ?? "",
      daysSince ?? "",
      bucketFor(daysSince),
      currency,
    ]);
  }
  return toCsv(headers, rows);
}
