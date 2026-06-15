// Setup module. V1 surfaces a single concern: staff. Two sections —
// active members and pending invites. "Add staff" dialog is gated by
// the setup.staff.invite capability; cashiers see the page (it's on
// their nav after #265's caps split) but no Add button.
//
// Member rows show role + UUID short (real names land with #287).
// Pending rows show contact (phone or email) verbatim since the
// owner just typed them.

import { getTranslations, getLocale } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Can } from "@/components/auth/can";
import { AddStaffDialog } from "@/components/setup/add-staff-dialog";

type MembershipRow = {
  user_id: string;
  is_active: boolean;
  role_id: string;
};
type RoleRow = { id: string; code: string };
type InviteRow = {
  id: string;
  phone: string | null;
  email: string | null;
  role_code: string;
  expires_at: string;
};

export default async function SetupPage() {
  const t = await getTranslations("setup");
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
  const [membersRes, rolesRes, invitesRes, userRes] = await Promise.all([
    supabase
      .from("shop_membership")
      .select("user_id, is_active, role_id")
      .eq("shop_id", currentShop.id),
    supabase.from("shop_role").select("id, code"),
    supabase
      .from("shop_invite")
      .select("id, phone, email, role_code, expires_at")
      .eq("shop_id", currentShop.id)
      .is("accepted_at", null)
      .order("created_at", { ascending: false }),
    supabase.auth.getUser(),
  ]);
  for (const r of [membersRes, rolesRes, invitesRes]) {
    if (r.error) {
      console.error("[setup] fetch failed:", r.error);
      throw r.error;
    }
  }

  const currentUserId = userRes.data.user?.id ?? null;
  const roleCodeById = new Map(
    ((rolesRes.data ?? []) as RoleRow[]).map((r) => [r.id, r.code]),
  );
  const members = ((membersRes.data ?? []) as MembershipRow[]).filter(
    (m) => m.is_active,
  );
  const invites = (invitesRes.data ?? []) as InviteRow[];

  const dateFmt = new Intl.DateTimeFormat(locale, { dateStyle: "medium" });
  const roleLabel = (code: string) =>
    code === "owner" ? t("staff.roleOwner") : t("staff.roleCashier");

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            {t("title")}
          </h1>
          <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
        </div>
        <Can capability="setup.staff.invite">
          <AddStaffDialog shopId={currentShop.id} />
        </Can>
      </div>

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
                return (
                  <li
                    key={m.user_id}
                    className="flex items-center justify-between py-3 text-sm"
                  >
                    <div className="flex items-center gap-2">
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
                    <span className="text-sm font-medium">
                      {roleLabel(roleCodeById.get(m.role_id) ?? "")}
                    </span>
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">
            {t("staff.pendingHeader")} ({invites.length})
          </CardTitle>
        </CardHeader>
        <CardContent>
          {invites.length === 0 ? (
            <p className="py-4 text-sm text-muted-foreground">
              {t("staff.pendingEmpty")}
            </p>
          ) : (
            <ul className="divide-y">
              {invites.map((iv) => (
                <li
                  key={iv.id}
                  className="flex items-center justify-between gap-4 py-3 text-sm"
                >
                  <span className="font-medium">{iv.phone ?? iv.email}</span>
                  <div className="flex items-center gap-3 text-xs text-muted-foreground">
                    <span>{roleLabel(iv.role_code)}</span>
                    <span className="tabular-nums">
                      {dateFmt.format(new Date(iv.expires_at))}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
