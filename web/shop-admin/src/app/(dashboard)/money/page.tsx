// Money module hub. Four tabs: Payments | Expenses | P&L | Cash.
// Payments is wired today; the others render a "coming soon" card
// until their iterations land.

import { getTranslations, getLocale } from "next-intl/server";
import { historyPageLimit } from "shared";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent } from "@/components/ui/card";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  PaymentsTable,
  type Payment,
} from "@/components/money/payments-table";
import {
  ExpensesTable,
  type Expense,
} from "@/components/money/expenses-table";

type PaymentRow = {
  payment_id: string;
  occurred_at: string;
  party_id: string | null;
  party_name: string | null;
  amount: number | string;
  direction: "I" | "O";
  payment_method_code: string | null;
  notes: string | null;
};

export default async function MoneyPage() {
  const t = await getTranslations("money");
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
  const [paymentsRes, expensesRes] = await Promise.all([
    supabase.rpc("list_payments", {
      p_shop_id: currentShop.id,
      p_limit: historyPageLimit,
    }),
    supabase.rpc("list_expenses", {
      p_shop_id: currentShop.id,
      p_limit: historyPageLimit,
      p_locale: locale,
    }),
  ]);
  if (paymentsRes.error) {
    console.error("[money] list_payments failed:", paymentsRes.error);
    throw paymentsRes.error;
  }
  if (expensesRes.error) {
    console.error("[money] list_expenses failed:", expensesRes.error);
    throw expensesRes.error;
  }

  const payments: Payment[] = (
    (paymentsRes.data ?? []) as PaymentRow[]
  ).map((r) => ({
    payment_id: r.payment_id,
    occurred_at: r.occurred_at,
    party_name: r.party_name,
    amount: Number(r.amount ?? 0),
    direction: r.direction,
    payment_method_code: r.payment_method_code,
    notes: r.notes,
  }));

  type ExpenseRow = {
    txn_id: string;
    occurred_at: string;
    amount: number | string;
    payment_method_code: string | null;
    category_id: string | null;
    category_name: string | null;
    notes: string | null;
  };
  const expenses: Expense[] = ((expensesRes.data ?? []) as ExpenseRow[]).map(
    (r) => ({
      txn_id: r.txn_id,
      occurred_at: r.occurred_at,
      category_name: r.category_name,
      amount: Number(r.amount ?? 0),
      payment_method_code: r.payment_method_code,
      notes: r.notes,
    }),
  );

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <h1 className="text-2xl font-semibold tracking-tight">
        {currentShop.name}
      </h1>
      <Tabs defaultValue="payments" className="w-full">
        <TabsList>
          <TabsTrigger value="payments">
            {t("tabPayments")} ({payments.length})
          </TabsTrigger>
          <TabsTrigger value="expenses">
            {t("tabExpenses")} ({expenses.length})
          </TabsTrigger>
          <TabsTrigger value="profit">{t("tabProfit")}</TabsTrigger>
          <TabsTrigger value="cash">{t("tabCash")}</TabsTrigger>
        </TabsList>
        <TabsContent value="payments" className="mt-4">
          <PaymentsTable
            rows={payments}
            currencyCode={currentShop.currency_code}
            locale={locale}
          />
        </TabsContent>
        <TabsContent value="expenses" className="mt-4">
          <ExpensesTable
            rows={expenses}
            currencyCode={currentShop.currency_code}
            locale={locale}
          />
        </TabsContent>
        <TabsContent value="profit" className="mt-4">
          <ComingSoon />
        </TabsContent>
        <TabsContent value="cash" className="mt-4">
          <ComingSoon />
        </TabsContent>
      </Tabs>
    </div>
  );
}

async function ComingSoon() {
  const t = await getTranslations("money.comingSoon");
  return (
    <Card>
      <CardContent className="py-12 text-center">
        <h3 className="text-base font-medium">{t("title")}</h3>
        <p className="mt-1 text-sm text-muted-foreground">{t("description")}</p>
      </CardContent>
    </Card>
  );
}
