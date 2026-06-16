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
import {
  AuditFilters,
  type ActionOption,
  type ActorOption,
} from "@/components/audit/audit-filters";
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

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<{
    action?: string;
    from?: string;
    to?: string;
    actor?: string;
  }>;
}) {
  const t = await getTranslations("audit");
  const locale = await getLocale();
  const { currentShop, capabilities } = await getCurrentShop();
  const canExport = capabilities.includes("audit.export");
  const {
    action: actionCode,
    from,
    to,
    actor: actorUserId,
  } = await searchParams;

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
  // Build the filtered events query — action_code + date range from
  // searchParams. PostgREST chains gte/lt on a timestamp; date-only
  // strings parse as midnight in the request's session timezone,
  // close enough for the filter granularity.
  let eventsQuery = supabase
    .from("audit_log")
    .select(
      "id, occurred_at, action_code, entity_type, entity_id, source, actor_user_id",
    )
    .eq("shop_id", currentShop.id)
    .order("occurred_at", { ascending: false })
    .limit(PAGE_LIMIT);
  if (actionCode) {
    eventsQuery = eventsQuery.eq("action_code", actionCode);
  }
  if (actorUserId) {
    eventsQuery = eventsQuery.eq("actor_user_id", actorUserId);
  }
  if (from) {
    eventsQuery = eventsQuery.gte("occurred_at", from);
  }
  if (to) {
    // Add one day so "to=2026-06-16" includes the whole 16th.
    const toExclusive = new Date(to);
    toExclusive.setUTCDate(toExclusive.getUTCDate() + 1);
    eventsQuery = eventsQuery.lt(
      "occurred_at",
      toExclusive.toISOString().slice(0, 10),
    );
  }

  const [eventsRes, actionsRes, profilesRes, membersRes, userRes] =
    await Promise.all([
      eventsQuery,
      supabase
        .from("audit_action_code")
        .select("code, description")
        .order("code"),
      supabase.from("user_profile").select("user_id, display_name"),
      supabase
        .from("shop_membership")
        .select("user_id, is_active")
        .eq("shop_id", currentShop.id)
        .eq("is_active", true),
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
  if (profilesRes.error) {
    console.error("[audit] user_profile fetch failed:", profilesRes.error);
    // Soft failure — keep rendering with UUID fallbacks.
  }
  if (membersRes.error) {
    console.error("[audit] shop_membership fetch failed:", membersRes.error);
    // Soft failure — actor dropdown will just be empty.
  }

  const descByCode = new Map(
    ((actionsRes.data ?? []) as ActionRow[]).map((r) => [
      r.code,
      r.description ?? r.code,
    ]),
  );
  const nameByUserId = new Map(
    ((profilesRes.data ?? []) as Array<{
      user_id: string;
      display_name: string;
    }>).map((p) => [p.user_id, p.display_name]),
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
    actor_display_name:
      r.actor_user_id !== null
        ? (nameByUserId.get(r.actor_user_id) ?? null)
        : null,
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
      <AuditFilters
        actions={
          (
            (actionsRes.data ?? []) as Array<{
              code: string;
              description: string | null;
            }>
          ).map<ActionOption>((r) => ({
            code: r.code,
            label: r.description ?? r.code,
          }))
        }
        actors={(
          (membersRes.data ?? []) as Array<{ user_id: string }>
        )
          .map<ActorOption>((m) => ({
            userId: m.user_id,
            label:
              nameByUserId.get(m.user_id) ??
              `${t("actorUnnamed")} (${m.user_id.slice(0, 8)})`,
          }))
          .sort((a, b) => a.label.localeCompare(b.label, locale))}
        initialAction={actionCode ?? null}
        initialActor={actorUserId ?? null}
        initialFrom={from ?? null}
        initialTo={to ?? null}
      />
      <AuditTable rows={entries} locale={locale} />
    </div>
  );
}
