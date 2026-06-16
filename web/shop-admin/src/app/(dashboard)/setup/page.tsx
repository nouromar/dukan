// Setup module. V1 surfaces:
//   1. My profile — current viewer edits their display_name.
//   2. Staff list — active members with display_name + join date.
//   3. Pending invites — contact + role + invite date + expiry.
//
// "Add staff" dialog is gated by the setup.staff.invite capability;
// cashiers see the page but no Add button.
//
// Display names + join/invite dates queried through user_profile +
// shop_membership.created_at. UUID short fallback for users who
// haven't set a name yet.

import { getTranslations, getLocale } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Can } from "@/components/auth/can";
import { AddStaffDialog } from "@/components/setup/add-staff-dialog";
import {
  ShopSettingsCard,
  type CurrencyOption,
  type LanguageOption,
} from "@/components/setup/shop-settings-card";

type MembershipRow = {
  user_id: string;
  is_active: boolean;
  role_id: string;
  created_at: string;
  updated_at: string;
};
type RoleRow = { id: string; code: string };
type InviteRow = {
  id: string;
  phone: string | null;
  email: string | null;
  display_name: string | null;
  role_code: string;
  expires_at: string;
  created_at: string;
};
type ProfileRow = { user_id: string; display_name: string };

// Display-name self-edit lives in the top-bar user menu (see
// UserMenuPanel). Keeping it out of /setup keeps that page focused
// on shop-level config + staff list.

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
  const [
    membersRes,
    rolesRes,
    invitesRes,
    profilesRes,
    userRes,
    currenciesRes,
    languagesRes,
  ] = await Promise.all([
    supabase
      .from("shop_membership")
      .select("user_id, is_active, role_id, created_at, updated_at")
      .eq("shop_id", currentShop.id),
    supabase.from("shop_role").select("id, code"),
    supabase
      .from("shop_invite")
      .select(
        "id, phone, email, display_name, role_code, expires_at, created_at",
      )
      .eq("shop_id", currentShop.id)
      .is("accepted_at", null)
      .order("created_at", { ascending: false }),
    supabase.from("user_profile").select("user_id, display_name"),
    supabase.auth.getUser(),
    supabase.from("currency").select("code, symbol").order("code"),
    supabase.from("language").select("code, default_label").order("code"),
  ]);
  for (const r of [membersRes, rolesRes, invitesRes, profilesRes]) {
    if (r.error) {
      console.error("[setup] fetch failed:", r.error);
      throw r.error;
    }
  }
  const currencies: CurrencyOption[] = (
    (currenciesRes.data ?? []) as Array<{ code: string; symbol: string | null }>
  ).map((c) => ({ code: c.code, label: c.symbol ?? c.code }));
  const languages: LanguageOption[] = (
    (languagesRes.data ?? []) as Array<{ code: string; default_label: string }>
  ).map((l) => ({ code: l.code, label: l.default_label }));

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

      <Can capability="setup.shop.edit">
        <ShopSettingsCard
          shopId={currentShop.id}
          initialName={currentShop.name}
          initialCurrencyCode={currentShop.currency_code}
          initialLanguageCode={currentShop.default_language_code ?? "en"}
          currencies={currencies}
          languages={languages}
        />
      </Can>

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
                  <div className="flex flex-col">
                    {iv.display_name ? (
                      <span className="font-medium">{iv.display_name}</span>
                    ) : null}
                    <span
                      className={
                        iv.display_name
                          ? "text-xs text-muted-foreground"
                          : "font-medium"
                      }
                    >
                      {iv.phone ?? iv.email}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 text-xs text-muted-foreground">
                    <span>{roleLabel(iv.role_code)}</span>
                    <span className="tabular-nums">
                      {t("staff.columns.invited")}:{" "}
                      {dateFmt.format(new Date(iv.created_at))}
                    </span>
                    <span className="tabular-nums">
                      {t("staff.columns.expires")}:{" "}
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
