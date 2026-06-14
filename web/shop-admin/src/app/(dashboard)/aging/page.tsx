// Aging report. Per-party outstanding balance, with the bucket
// computed from the party's most-recent activity (latest sale OR
// receive OR payment).
//
// V1 uses "last activity" as the aging proxy — true per-sale
// aging (with payment allocations factored in) would need a SQL view
// over txn × payment_allocation that doesn't exist yet. The current
// approach is accurate enough for "who's been sitting on debt the
// longest" without adding a migration.

import Link from "next/link";
import { getTranslations, getLocale } from "next-intl/server";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  AgingTable,
  type AgingBucket,
  type AgingRow,
} from "@/components/aging/aging-table";

type PartyTypeRow = { id: string; code: string };
type PartyRow = {
  id: string;
  name: string;
  receivable: number | string | null;
  payable: number | string | null;
  type_id: string;
};
type TxnTimeRow = { party_id: string | null; occurred_at: string };

const DAY_MS = 24 * 60 * 60 * 1000;

function bucketFor(daysSince: number | null): AgingBucket {
  if (daysSince === null) return "never";
  if (daysSince <= 30) return "current";
  if (daysSince <= 60) return "over30";
  if (daysSince <= 90) return "over60";
  return "over90";
}

function ageRank(b: AgingBucket): number {
  // Higher number = older = sorts to top.
  return { current: 0, over30: 1, over60: 2, over90: 3, never: 4 }[b];
}

export default async function AgingPage() {
  const t = await getTranslations("aging");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();

  if (!currentShop) {
    return (
      <div className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-xl font-medium">{t("noShop.title")}</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          {t("noShop.description")}
        </p>
      </div>
    );
  }

  const supabase = await createSupabaseServerClient();
  const [partiesRes, typesRes, txnsRes, paymentsRes] = await Promise.all([
    supabase
      .from("party")
      .select("id, name, receivable, payable, type_id")
      .eq("shop_id", currentShop.id)
      .eq("is_active", true),
    supabase.from("party_type").select("id, code"),
    supabase
      .from("txn")
      .select("party_id, occurred_at")
      .eq("shop_id", currentShop.id)
      .not("party_id", "is", null),
    supabase
      .from("payment")
      .select("party_id, occurred_at")
      .eq("shop_id", currentShop.id)
      .not("party_id", "is", null),
  ]);
  for (const r of [partiesRes, typesRes, txnsRes, paymentsRes]) {
    if (r.error) {
      console.error("[aging] fetch failed:", r.error);
      throw r.error;
    }
  }

  const typeById = new Map(
    ((typesRes.data ?? []) as PartyTypeRow[]).map((tt) => [tt.id, tt.code]),
  );
  const lastActivityById = new Map<string, string>();
  const apply = (party_id: string | null, occurred_at: string) => {
    if (!party_id) return;
    const prev = lastActivityById.get(party_id);
    if (!prev || prev < occurred_at) {
      lastActivityById.set(party_id, occurred_at);
    }
  };
  for (const r of (txnsRes.data ?? []) as TxnTimeRow[]) {
    apply(r.party_id, r.occurred_at);
  }
  for (const r of (paymentsRes.data ?? []) as TxnTimeRow[]) {
    apply(r.party_id, r.occurred_at);
  }

  const now = Date.now();
  const buildRows = (kind: "customer" | "supplier"): AgingRow[] => {
    const rows: AgingRow[] = [];
    for (const p of (partiesRes.data ?? []) as PartyRow[]) {
      if (typeById.get(p.type_id) !== kind) continue;
      const balance = Number(
        kind === "customer" ? (p.receivable ?? 0) : (p.payable ?? 0),
      );
      if (balance <= 0) continue;
      const lastActivity = lastActivityById.get(p.id) ?? null;
      const daysSince =
        lastActivity === null
          ? null
          : Math.floor((now - new Date(lastActivity).getTime()) / DAY_MS);
      rows.push({
        party_id: p.id,
        name: p.name,
        balance,
        last_activity_at: lastActivity,
        bucket: bucketFor(daysSince),
        days_since: daysSince,
      });
    }
    return rows.sort(
      (a, b) =>
        ageRank(b.bucket) - ageRank(a.bucket) || b.balance - a.balance,
    );
  };

  const receivables = buildRows("customer");
  const payables = buildRows("supplier");

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-col gap-1">
        <Link
          href="/people"
          className="text-sm text-muted-foreground hover:text-foreground"
        >
          {t("back")}
        </Link>
        <h1 className="text-2xl font-semibold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>

      <Tabs defaultValue="receivables" className="w-full">
        <TabsList>
          <TabsTrigger value="receivables">
            {t("tabReceivables")} ({receivables.length})
          </TabsTrigger>
          <TabsTrigger value="payables">
            {t("tabPayables")} ({payables.length})
          </TabsTrigger>
        </TabsList>
        <TabsContent value="receivables" className="mt-4">
          <AgingTable
            rows={receivables}
            currencyCode={currentShop.currency_code}
            locale={locale}
            emptyTitle={t("empty.receivablesTitle")}
            emptyDescription={t("empty.receivablesDescription")}
          />
        </TabsContent>
        <TabsContent value="payables" className="mt-4">
          <AgingTable
            rows={payables}
            currencyCode={currentShop.currency_code}
            locale={locale}
            emptyTitle={t("empty.payablesTitle")}
            emptyDescription={t("empty.payablesDescription")}
          />
        </TabsContent>
      </Tabs>
    </div>
  );
}
