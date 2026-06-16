// Staff tab — active members with display name, role, and join date.
// Cashiers can view (read-only); only owners see the Add staff button
// (rendered by the layout).

import { getTranslations, getLocale } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type MembershipRow = {
  user_id: string;
  is_active: boolean;
  role_id: string;
  created_at: string;
  updated_at: string;
};
type RoleRow = { id: string; code: string };
type ProfileRow = { user_id: string; display_name: string };

export default async function SetupStaffPage() {
  const t = await getTranslations("setup");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();
  if (!currentShop) return null;

  const supabase = await createSupabaseServerClient();
  const [membersRes, rolesRes, profilesRes, userRes] = await Promise.all([
    supabase
      .from("shop_membership")
      .select("user_id, is_active, role_id, created_at, updated_at")
      .eq("shop_id", currentShop.id),
    supabase.from("shop_role").select("id, code"),
    supabase.from("user_profile").select("user_id, display_name"),
    supabase.auth.getUser(),
  ]);
  for (const r of [membersRes, rolesRes, profilesRes]) {
    if (r.error) {
      console.error("[setup/staff] fetch failed:", r.error);
      throw r.error;
    }
  }

  const currentUserId = userRes.data.user?.id ?? null;
  const roleCodeById = new Map(
    ((rolesRes.data ?? []) as RoleRow[]).map((r) => [r.id, r.code]),
  );
  const nameByUserId = new Map(
    ((profilesRes.data ?? []) as ProfileRow[]).map((p) => [
      p.user_id,
      p.display_name,
    ]),
  );

  const members = ((membersRes.data ?? []) as MembershipRow[]).filter(
    (m) => m.is_active,
  );

  const dateFmt = new Intl.DateTimeFormat(locale, { dateStyle: "medium" });
  const roleLabel = (code: string) =>
    code === "owner" ? t("staff.roleOwner") : t("staff.roleCashier");

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-medium">
          {t("staff.membersHeader")} ({members.length})
        </CardTitle>
      </CardHeader>
      <CardContent>
        {members.length === 0 ? (
          <p className="py-4 text-sm text-muted-foreground">
            {t("staff.membersEmpty")}
          </p>
        ) : (
          <ul className="divide-y">
            {members.map((m) => {
              const isSelf = m.user_id === currentUserId;
              const displayName = nameByUserId.get(m.user_id);
              return (
                <li
                  key={m.user_id}
                  className="flex items-center justify-between gap-4 py-3 text-sm"
                >
                  <div className="flex items-center gap-2">
                    {displayName ? (
                      <span className="font-medium">{displayName}</span>
                    ) : (
                      <span className="italic text-muted-foreground">
                        {t("staff.unnamed")}
                      </span>
                    )}
                    <span
                      className="font-mono text-xs text-muted-foreground"
                      title={m.user_id}
                    >
                      {m.user_id.slice(0, 8)}
                    </span>
                    {isSelf ? (
                      <span className="rounded bg-primary/10 px-1.5 py-0.5 text-xs font-medium text-primary">
                        {t("staff.youTag")}
                      </span>
                    ) : null}
                  </div>
                  <div className="flex items-center gap-4 text-xs text-muted-foreground">
                    <span className="tabular-nums">
                      {t("staff.columns.joined")}:{" "}
                      {dateFmt.format(new Date(m.created_at))}
                    </span>
                    <span className="text-sm font-medium text-foreground">
                      {roleLabel(roleCodeById.get(m.role_id) ?? "")}
                    </span>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
