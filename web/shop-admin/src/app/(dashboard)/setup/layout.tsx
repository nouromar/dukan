// Shared shell for the Setup module. Renders the page title, the
// owner-gated Add staff button, and a horizontal tab strip that
// navigates between /setup/general, /setup/staff, and /setup/invites.
// Each tab is its own route, so the URL is deep-linkable and the
// browser back/forward behaves as expected.

import { getTranslations } from "next-intl/server";
import { getCurrentShop } from "@/lib/current-shop";
import { Can } from "@/components/auth/can";
import { AddStaffDialog } from "@/components/setup/add-staff-dialog";
import { SetupTabs } from "@/components/setup/setup-tabs";

export default async function SetupLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const t = await getTranslations("setup");
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
      <SetupTabs />
      {children}
    </div>
  );
}
