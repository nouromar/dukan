// Audit log detail. The list view collapses each row to time / actor /
// action / entity for scanning; this page pulls the full payload that
// the row hides:
//
//   * Header — action label + code.
//   * Meta — when, who, source, reason, client_op_id.
//   * Entity — type + id with a link back to the entity page (sale /
//     product / party) when we know how to render it.
//   * Diff — top-level keys of before_state vs after_state. Shows
//     only changed keys + adds/removals. Nested objects render as
//     compact JSON.
//   * Related — last 20 audit events that share this entity_id.
//
// RLS already enforces the shop boundary — this page just trusts the
// row that came back.

import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations, getLocale } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type AuditRow = {
  id: string;
  shop_id: string;
  occurred_at: string;
  action_code: string;
  entity_type: string;
  entity_id: string | null;
  entity_ids: string[] | null;
  before_state: Record<string, unknown> | null;
  after_state: Record<string, unknown> | null;
  reason: string | null;
  client_op_id: string | null;
  source: string;
  actor_user_id: string | null;
};

const SOURCE_KEYS: Record<string, string> = {
  mobile: "mobile",
  shop_admin_web: "shop_admin_web",
  system_admin_web: "system_admin_web",
  rpc: "rpc",
  system: "system",
};

export default async function AuditDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const t = await getTranslations("audit");
  const td = await getTranslations("audit.detail");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();
  if (!currentShop) notFound();

  const supabase = await createSupabaseServerClient();
  const { data: row, error } = await supabase
    .from("audit_log")
    .select(
      "id, shop_id, occurred_at, action_code, entity_type, entity_id, entity_ids, before_state, after_state, reason, client_op_id, source, actor_user_id",
    )
    .eq("shop_id", currentShop.id)
    .eq("id", id)
    .maybeSingle();
  if (error) {
    console.error("[audit-detail] fetch failed:", error);
    throw error;
  }
  if (!row) notFound();
  const event = row as AuditRow;

  const [actionRes, actorRes, relatedRes] = await Promise.all([
    supabase
      .from("audit_action_code")
      .select("code, description")
      .eq("code", event.action_code)
      .maybeSingle(),
    event.actor_user_id
      ? supabase
          .from("user_profile")
          .select("user_id, display_name")
          .eq("user_id", event.actor_user_id)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    event.entity_id
      ? supabase
          .from("audit_log")
          .select(
            "id, occurred_at, action_code, source, actor_user_id",
          )
          .eq("shop_id", currentShop.id)
          .eq("entity_id", event.entity_id)
          .neq("id", event.id)
          .order("occurred_at", { ascending: false })
          .limit(20)
          .then(async (r) => {
            // Resolve actor names for the related list in one query.
            const ids = Array.from(
              new Set(
                ((r.data ?? []) as Array<{
                  actor_user_id: string | null;
                }>)
                  .map((x) => x.actor_user_id)
                  .filter((x): x is string => x !== null),
              ),
            );
            const profiles =
              ids.length === 0
                ? { data: [] as Array<{ user_id: string; display_name: string }> }
                : await supabase
                    .from("user_profile")
                    .select("user_id, display_name")
                    .in("user_id", ids);
            return { ...r, profiles };
          })
      : Promise.resolve({
          data: [],
          error: null,
          profiles: { data: [] },
        }),
  ]);

  const actionLabel =
    (actionRes.data as { description: string | null } | null)?.description ??
    event.action_code;
  const actorProfile = (actorRes.data as {
    user_id: string;
    display_name: string;
  } | null) ?? null;

  const fmt = new Intl.DateTimeFormat(locale, {
    dateStyle: "medium",
    timeStyle: "short",
  });

  const diff = buildDiff(event.before_state, event.after_state);
  const entityHref = mapEntityHref(event.entity_type, event.entity_id);

  const relatedRows = (relatedRes.data ?? []) as Array<{
    id: string;
    occurred_at: string;
    action_code: string;
    source: string;
    actor_user_id: string | null;
  }>;
  const relatedActorNames = new Map(
    (
      ((relatedRes as { profiles?: { data: Array<{ user_id: string; display_name: string }> } })
        .profiles?.data ?? [])
    ).map((p) => [p.user_id, p.display_name]),
  );

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <Link
        href="/audit"
        className="text-sm text-muted-foreground hover:text-foreground"
      >
        {td("back")}
      </Link>

      <header className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">
          {actionLabel}
        </h1>
        <p className="font-mono text-xs text-muted-foreground">
          {event.action_code}
        </p>
      </header>

      <Card>
        <CardContent className="grid grid-cols-1 gap-3 pt-6 sm:grid-cols-2">
          <MetaRow label={td("when")}>{fmt.format(new Date(event.occurred_at))}</MetaRow>
          <MetaRow label={td("who")}>
            {event.actor_user_id ? (
              <span className="flex flex-col">
                {actorProfile?.display_name ? (
                  <span className="font-medium">
                    {actorProfile.display_name}
                  </span>
                ) : (
                  <span className="italic text-muted-foreground">
                    {t("actorUnnamed")}
                  </span>
                )}
                <span className="font-mono text-xs text-muted-foreground">
                  {event.actor_user_id.slice(0, 8)}
                </span>
              </span>
            ) : (
              <span className="text-muted-foreground">{t("actorSystem")}</span>
            )}
          </MetaRow>
          <MetaRow label={td("source")}>
            <span className="rounded bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
              {t(`sources.${SOURCE_KEYS[event.source] ?? "system"}` as "sources.mobile")}
            </span>
          </MetaRow>
          <MetaRow label={td("entity")}>
            <span className="flex items-center gap-2 text-sm">
              <span className="font-medium">{event.entity_type}</span>
              {event.entity_id ? (
                entityHref ? (
                  <Link
                    href={entityHref}
                    className="font-mono text-xs text-primary hover:underline"
                    title={event.entity_id}
                  >
                    {event.entity_id.slice(0, 8)} →
                  </Link>
                ) : (
                  <span
                    className="font-mono text-xs text-muted-foreground"
                    title={event.entity_id}
                  >
                    {event.entity_id.slice(0, 8)}
                  </span>
                )
              ) : null}
            </span>
          </MetaRow>
          {event.reason ? (
            <MetaRow label={td("reason")}>{event.reason}</MetaRow>
          ) : null}
          {event.client_op_id ? (
            <MetaRow label={td("clientOpId")}>
              <span
                className="font-mono text-xs text-muted-foreground"
                title={event.client_op_id}
              >
                {event.client_op_id.slice(0, 16)}
              </span>
            </MetaRow>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">
            {td("changes")}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {diff.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {td("noChanges")}
            </p>
          ) : (
            <ul className="divide-y text-sm">
              {diff.map((d) => (
                <li
                  key={d.key}
                  className="grid grid-cols-1 gap-1 py-2 sm:grid-cols-[10rem_1fr]"
                >
                  <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {d.key}
                  </span>
                  <div className="space-y-0.5">
                    {d.kind === "added" ? (
                      <span className="text-emerald-700 dark:text-emerald-400">
                        + {formatValue(d.after)}
                      </span>
                    ) : d.kind === "removed" ? (
                      <span className="text-destructive line-through">
                        − {formatValue(d.before)}
                      </span>
                    ) : (
                      <span className="block">
                        <span className="text-muted-foreground line-through">
                          {formatValue(d.before)}
                        </span>
                        <span className="mx-1.5 text-muted-foreground">→</span>
                        <span className="font-medium">
                          {formatValue(d.after)}
                        </span>
                      </span>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      {event.entity_id ? (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">
              {td("related")}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {relatedRows.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {td("noRelated")}
              </p>
            ) : (
              <ul className="divide-y text-sm">
                {relatedRows.map((r) => (
                  <li key={r.id} className="py-2">
                    <Link
                      href={`/audit/${r.id}`}
                      className="flex items-center justify-between gap-3 hover:text-primary"
                    >
                      <span className="flex-1 truncate font-medium">
                        {r.action_code}
                      </span>
                      <span className="text-xs text-muted-foreground">
                        {r.actor_user_id
                          ? (relatedActorNames.get(r.actor_user_id) ??
                            r.actor_user_id.slice(0, 8))
                          : t("actorSystem")}
                      </span>
                      <span className="tabular-nums text-xs text-muted-foreground">
                        {fmt.format(new Date(r.occurred_at))}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

function MetaRow({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        {label}
      </span>
      <div className="text-sm">{children}</div>
    </div>
  );
}

type DiffEntry =
  | { kind: "added"; key: string; after: unknown }
  | { kind: "removed"; key: string; before: unknown }
  | { kind: "changed"; key: string; before: unknown; after: unknown };

function buildDiff(
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null,
): DiffEntry[] {
  if (!before && !after) return [];
  const keys = new Set<string>([
    ...Object.keys(before ?? {}),
    ...Object.keys(after ?? {}),
  ]);
  const result: DiffEntry[] = [];
  for (const key of Array.from(keys).sort()) {
    const b = before?.[key];
    const a = after?.[key];
    const hasBefore = before !== null && key in before;
    const hasAfter = after !== null && key in after;
    if (hasBefore && !hasAfter) {
      result.push({ kind: "removed", key, before: b });
    } else if (!hasBefore && hasAfter) {
      result.push({ kind: "added", key, after: a });
    } else if (!shallowEqual(b, a)) {
      result.push({ kind: "changed", key, before: b, after: a });
    }
  }
  return result;
}

function shallowEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === null || b === null) return false;
  if (typeof a !== typeof b) return false;
  if (typeof a === "object") {
    return JSON.stringify(a) === JSON.stringify(b);
  }
  return false;
}

function formatValue(v: unknown): string {
  if (v === null || v === undefined) return "—";
  if (typeof v === "string") return v;
  if (typeof v === "number") return v.toString();
  if (typeof v === "boolean") return v ? "true" : "false";
  return JSON.stringify(v);
}

function mapEntityHref(
  entityType: string,
  entityId: string | null,
): string | null {
  if (!entityId) return null;
  switch (entityType) {
    case "transaction":
      // Most transaction audits are sales; receives + expenses currently
      // don't have detail routes. The sales page will 404 cleanly if
      // this turns out to be a non-sale.
      return `/sales/${entityId}`;
    case "shop_item":
      return `/inventory/${entityId}`;
    case "party":
      return `/people/${entityId}`;
    default:
      return null;
  }
}
