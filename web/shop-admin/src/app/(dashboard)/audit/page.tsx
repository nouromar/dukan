// Audit log feed. Last 100 events for the current shop, with the
// human-readable action label joined from audit_action_code. RLS
// already gates this to shop members; the page renders only what the
// signed-in user can already see.
//
// Capability-gated in left-rail.tsx behind audit.view, so cashiers
// never see this nav item.

import { getTranslations, getLocale } from "next-intl/server";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  AuditTable,
  type AuditEntry,
} from "@/components/audit/audit-table";
import { ExportCsvButton } from "@/components/shared/export-csv-button";

const PAGE_LIMIT = 100;

type AuditRow = {
  id: string;
  occurred_at: string;
  action_code: string;
  entity_type: string;
  entity_id: string | null;
  source: string;
  actor_user_id: string | null;
};

type ActionRow = { code: string; description: string | null };

export default async function AuditPage() {
  const t = await getTranslations("audit");
  const locale = await getLocale();
  const { currentShop, capabilities } = await getCurrentShop();
  const canExport = capabilities.includes("audit.export");

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
  const [eventsRes, actionsRes, userRes] = await Promise.all([
    supabase
      .from("audit_log")
      .select(
        "id, occurred_at, action_code, entity_type, entity_id, source, actor_user_id",
      )
      .eq("shop_id", currentShop.id)
      .order("occurred_at", { ascending: false })
      .limit(PAGE_LIMIT),
    supabase.from("audit_action_code").select("code, description"),
    supabase.auth.getUser(),
  ]);
  const currentUserId = userRes.data.user?.id ?? null;
  if (eventsRes.error) {
    console.error("[audit] audit_log fetch failed:", eventsRes.error);
    throw eventsRes.error;
  }
  if (actionsRes.error) {
    console.error(
      "[audit] audit_action_code fetch failed:",
      actionsRes.error,
    );
    throw actionsRes.error;
  }

  const descByCode = new Map(
    ((actionsRes.data ?? []) as ActionRow[]).map((r) => [
      r.code,
      r.description ?? r.code,
    ]),
  );
  const entries: AuditEntry[] = (
    (eventsRes.data ?? []) as AuditRow[]
  ).map((r) => ({
    id: r.id,
    occurred_at: r.occurred_at,
    action_code: r.action_code,
    action_label: descByCode.get(r.action_code) ?? r.action_code,
    entity_type: r.entity_type,
    entity_id: r.entity_id,
    source: r.source,
    actor_user_id: r.actor_user_id,
    is_self:
      r.actor_user_id !== null && r.actor_user_id === currentUserId,
  }));

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-baseline gap-3">
          <h1 className="text-2xl font-semibold tracking-tight">
            {currentShop.name}
          </h1>
          <span className="text-sm text-muted-foreground">
            {entries.length === PAGE_LIMIT ? `${PAGE_LIMIT}+` : entries.length}
          </span>
        </div>
        {canExport ? <ExportCsvButton href="/api/export/audit" /> : null}
      </div>
      <AuditTable rows={entries} locale={locale} />
    </div>
  );
}
