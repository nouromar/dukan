// People module. Two tabs (Customers | Suppliers), each a sortable +
// searchable DataTable backed by the `party` table. Server component
// — RLS filters to the current shop's parties automatically.
//
// Balance column is shop-currency-formatted. Rows with positive
// balance are bolded so the user's eye lands on them first ("balance-
// first sort" per design doc § People).

import { getTranslations, getLocale } from "next-intl/server";
import { formatMoney } from "shared";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PeopleTabs } from "@/components/people/people-tabs";
import type { Party } from "@/components/people/parties-table";

type PartyRow = {
  id: string;
  name: string;
  phone: string | null;
  receivable: number | string | null;
  payable: number | string | null;
  type: { code: string } | null;
};

export default async function PeoplePage() {
  const t = await getTranslations("people");
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
  // RLS limits to the user's accessible shops; explicit shop_id filter
  // narrows to just this shop (an org-owner has access to all shops in
  // their org). is_active filter hides soft-deleted parties.
  const { data: rows } = await supabase
    .from("party")
    .select("id, name, phone, receivable, payable, type:type_id(code)")
    .eq("shop_id", currentShop.id)
    .eq("is_active", true)
    .order("name", { ascending: true });

  const all = (rows as unknown as PartyRow[] | null) ?? [];
  const customers: Party[] = all
    .filter((r) => r.type?.code === "customer")
    .map((r) => ({
      id: r.id,
      name: r.name,
      phone: r.phone,
      balance: Number(r.receivable ?? 0),
    }))
    .sort((a, b) => b.balance - a.balance || a.name.localeCompare(b.name));
  const suppliers: Party[] = all
    .filter((r) => r.type?.code === "supplier")
    .map((r) => ({
      id: r.id,
      name: r.name,
      phone: r.phone,
      balance: Number(r.payable ?? 0),
    }))
    .sort((a, b) => b.balance - a.balance || a.name.localeCompare(b.name));

  // Bind the shop currency once so the table doesn't re-derive per
  // row. Locale comes from next-intl's resolved locale.
  const money = (n: number) =>
    formatMoney(n, currentShop.currency_code, locale);

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <h1 className="text-2xl font-semibold tracking-tight">
        {currentShop.name}
      </h1>
      <PeopleTabs
        customers={customers}
        suppliers={suppliers}
        formatMoney={money}
      />
    </div>
  );
}
