// Invites tab — pending shop_invite rows. Owner sends + cashier can
// read (RLS-gated). Accepted invites disappear from this list.

import { getTranslations, getLocale } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type InviteRow = {
  id: string;
  phone: string | null;
  email: string | null;
  display_name: string | null;
  role_code: string;
  expires_at: string;
  created_at: string;
};

export default async function SetupInvitesPage() {
  const t = await getTranslations("setup");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();
  if (!currentShop) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("shop_invite")
    .select("id, phone, email, display_name, role_code, expires_at, created_at")
    .eq("shop_id", currentShop.id)
    .is("accepted_at", null)
    .order("created_at", { ascending: false });
  if (error) {
    console.error("[setup/invites] fetch failed:", error);
    throw error;
  }
  const invites = (data ?? []) as InviteRow[];

  const dateFmt = new Intl.DateTimeFormat(locale, { dateStyle: "medium" });
  const roleLabel = (code: string) =>
    code === "owner" ? t("staff.roleOwner") : t("staff.roleCashier");

  return (
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
  );
}
