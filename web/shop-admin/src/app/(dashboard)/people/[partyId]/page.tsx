// Party detail. Single get_party_detail RPC call returns header +
// last 20 sales + last 20 receives + last 20 payments in one
// jsonb blob.

import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations, getLocale } from "next-intl/server";
import { formatMoney } from "shared";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  TransactionsList,
  PaymentsList,
  type TxnRow,
  type PaymentRow,
} from "@/components/people/detail/transactions-list";
import { EditPartyDialog } from "@/components/people/detail/edit-party-dialog";
import { Can } from "@/components/auth/can";

type PartyDetail = {
  header: {
    id: string;
    name: string;
    phone: string | null;
    type_code: "customer" | "supplier";
    receivable: number | string;
    payable: number | string;
    is_active: boolean;
  };
  sales: TxnRow[];
  receives: TxnRow[];
  payments: PaymentRow[];
};

export default async function PartyDetailPage({
  params,
}: {
  params: Promise<{ partyId: string }>;
}) {
  const { partyId } = await params;
  const t = await getTranslations("partyDetail");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();

  if (!currentShop) {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("get_party_detail", {
    p_shop_id: currentShop.id,
    p_party_id: partyId,
  });

  if (error) {
    // RPC throws 'party % not found' for missing/inaccessible ids —
    // surface as a 404.
    if (error.message?.includes("not found")) {
      notFound();
    }
    console.error("[party-detail] get_party_detail failed:", error);
    throw error;
  }

  const detail = data as PartyDetail | null;
  if (!detail) notFound();

  const isCustomer = detail.header.type_code === "customer";
  const balanceAmount = Number(
    isCustomer ? detail.header.receivable : detail.header.payable,
  );
  const balanceLabel = isCustomer
    ? t("balanceOwesYou")
    : t("balanceYouOwe");
  const money = (n: number) =>
    formatMoney(n, currentShop.currency_code, locale);

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <Link
        href="/people"
        className="text-sm text-muted-foreground hover:text-foreground"
      >
        {t("back")}
      </Link>

      <header className="flex items-start justify-between gap-4">
        <div className="space-y-2">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-semibold tracking-tight">
              {detail.header.name}
            </h1>
            <span className="rounded bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
              {isCustomer ? t("typeCustomer") : t("typeSupplier")}
            </span>
            {!detail.header.is_active ? (
              <span className="rounded bg-destructive/10 px-2 py-0.5 text-xs font-medium text-destructive">
                {t("inactive")}
              </span>
            ) : null}
          </div>
          <p className="text-sm text-muted-foreground">
            {detail.header.phone ?? t("noPhone")}
          </p>
        </div>
        <Can capability="people.party.edit">
          <EditPartyDialog
            shopId={currentShop.id}
            partyId={detail.header.id}
            initialName={detail.header.name}
            initialPhone={detail.header.phone}
          />
        </Can>
      </header>

      <Card>
        <CardContent className="pt-6">
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {balanceLabel}
          </div>
          <div
            className={
              balanceAmount > 0
                ? "text-3xl font-semibold tabular-nums"
                : "text-3xl font-semibold tabular-nums text-muted-foreground"
            }
          >
            {money(balanceAmount)}
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {isCustomer ? (
          <Card>
            <CardHeader>
              <CardTitle className="text-sm font-medium">
                {t("sectionsSales")}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <TransactionsList
                rows={detail.sales.map(coerceTxn)}
                currencyCode={currentShop.currency_code}
                locale={locale}
                emptyMessage={t("empty.sales")}
              />
            </CardContent>
          </Card>
        ) : (
          <Card>
            <CardHeader>
              <CardTitle className="text-sm font-medium">
                {t("sectionsReceives")}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <TransactionsList
                rows={detail.receives.map(coerceTxn)}
                currencyCode={currentShop.currency_code}
                locale={locale}
                emptyMessage={t("empty.receives")}
              />
            </CardContent>
          </Card>
        )}

        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">
              {t("sectionsPayments")}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <PaymentsList
              rows={detail.payments.map(coercePayment)}
              currencyCode={currentShop.currency_code}
              locale={locale}
              emptyMessage={t("empty.payments")}
            />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function coerceTxn(r: TxnRow): TxnRow {
  return {
    txn_id: r.txn_id,
    occurred_at: r.occurred_at,
    total_amount: Number(r.total_amount ?? 0),
    paid_amount: Number(r.paid_amount ?? 0),
    is_voided: Boolean(r.is_voided),
  };
}

function coercePayment(r: PaymentRow): PaymentRow {
  return {
    payment_id: r.payment_id,
    occurred_at: r.occurred_at,
    amount: Number(r.amount ?? 0),
    direction: r.direction,
  };
}
