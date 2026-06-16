// People module. Two tabs (Customers | Suppliers), each a sortable +
// searchable DataTable backed by the `party` table. Server component
// — RLS filters to the current shop's parties automatically.
//
// Balance column is shop-currency-formatted. Rows with positive
// balance are bolded so the user's eye lands on them first ("balance-
// first sort" per design doc § People).

import Link from "next/link";
import { getTranslations, getLocale } from "next-intl/server";
import { getCurrentShop } from "@/lib/current-shop";
import { ExportCsvButton } from "@/components/shared/export-csv-button";
import { AddPartyDialog } from "@/components/people/add-party-dialog";
import { ImportPartiesDialog } from "@/components/people/import-parties-dialog";
import { Can } from "@/components/auth/can";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PeopleTabs } from "@/components/people/people-tabs";
import type { Party } from "@/components/people/parties-table";

type PartyRow = {
  id: string;
  name: string;
  phone: string | null;
  receivable: number | string | null;
  payable: number | string | null;
  type_id: string;
};

type PartyTypeRow = { id: string; code: string };

export default async function PeoplePage() {
  const t = await getTranslations("people");
  const locale = await getLocale();
  const { currentShop, capabilities } = await getCurrentShop();
  const canExport = capabilities.includes("people.statement.export");

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
  // Two parallel queries instead of a PostgREST inline join — avoids
  // any auto-detection edge case when party has more than one FK to a
  // *_type table (it has both type_id and supplier_type_id).
  const [partiesRes, typesRes] = await Promise.all([
    supabase
      .from("party")
      .select("id, name, phone, receivable, payable, type_id")
      .eq("shop_id", currentShop.id)
      .eq("is_active", true)
      .order("name", { ascending: true }),
    supabase.from("party_type").select("id, code"),
  ]);
  if (partiesRes.error) {
    console.error("[people] party fetch failed:", partiesRes.error);
    throw partiesRes.error;
  }
  if (typesRes.error) {
    console.error("[people] party_type fetch failed:", typesRes.error);
    throw typesRes.error;
  }

  const typeById = new Map(
    ((typesRes.data ?? []) as PartyTypeRow[]).map((t) => [t.id, t.code]),
  );
  const all = (partiesRes.data ?? []) as PartyRow[];
  const customers: Party[] = all
    .filter((r) => typeById.get(r.type_id) === "customer")
    .map((r) => ({
      id: r.id,
      name: r.name,
      phone: r.phone,
      balance: Number(r.receivable ?? 0),
    }))
    .sort((a, b) => b.balance - a.balance || a.name.localeCompare(b.name));
  const suppliers: Party[] = all
    .filter((r) => typeById.get(r.type_id) === "supplier")
    .map((r) => ({
      id: r.id,
      name: r.name,
      phone: r.phone,
      balance: Number(r.payable ?? 0),
    }))
    .sort((a, b) => b.balance - a.balance || a.name.localeCompare(b.name));

  const tAging = await getTranslations("aging");

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold tracking-tight">
          {currentShop.name}
        </h1>
        <div className="flex items-center gap-3">
          {canExport ? (
            <>
              <ExportCsvButton href="/api/export/customers" />
              <ExportCsvButton href="/api/export/suppliers" />
            </>
          ) : null}
          <Link
            href="/aging"
            className="text-sm font-medium text-primary hover:underline"
          >
            {tAging("viewLink")}
          </Link>
          <Can capability="people.party.create">
            <ImportPartiesDialog shopId={currentShop.id} />
            <AddPartyDialog shopId={currentShop.id} />
          </Can>
        </div>
      </div>
      <PeopleTabs
        customers={customers}
        suppliers={suppliers}
        currencyCode={currentShop.currency_code}
        locale={locale}
      />
    </div>
  );
}
