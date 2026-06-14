// Single-shop Overview dashboard. KPI hero row + top-5 customers /
// suppliers lists. Backed by get_today_summary RPC for the daily-window
// numbers and list_receivables / list_payables for the balance lists.
// Server component — all data fetched in parallel before render.

import {
  Receipt,
  TrendingUp,
  ArrowDownToLine,
  ArrowUpFromLine,
  Boxes,
} from "lucide-react";
import { getTranslations, getLocale } from "next-intl/server";
import { formatMoney, formatCount } from "shared";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { KpiCard } from "@/components/overview/kpi-card";
import {
  BalanceList,
  type PartyBalance,
} from "@/components/overview/balance-list";
import { getCurrentShop } from "@/lib/current-shop";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const TOP_N = 5;

// Shapes returned by get_today_summary RPC.
type TodaySummary = {
  sales_today?: { count?: number; total?: number };
  receivables_total?: number;
  payables_total?: number;
  low_stock_count?: number;
};

type ListBalanceRow = {
  party_id: string;
  name: string;
  receivable?: number;
  payable?: number;
};

export default async function OverviewPage() {
  const t = await getTranslations("overview");
  const locale = await getLocale();
  const { currentShop } = await getCurrentShop();

  if (!currentShop) {
    return <NoShopEmpty />;
  }

  const supabase = await createSupabaseServerClient();
  const [summaryRes, receivablesRes, payablesRes] = await Promise.all([
    supabase.rpc("get_today_summary", {
      p_shop_id: currentShop.id,
      p_locale: locale,
    }),
    supabase.rpc("list_receivables", {
      p_shop_id: currentShop.id,
      p_locale: locale,
    }),
    supabase.rpc("list_payables", {
      p_shop_id: currentShop.id,
      p_locale: locale,
    }),
  ]);

  const summary: TodaySummary =
    (summaryRes.data as TodaySummary | null) ?? {};
  const receivableRows = (receivablesRes.data as ListBalanceRow[] | null) ?? [];
  const payableRows = (payablesRes.data as ListBalanceRow[] | null) ?? [];

  const salesTodayTotal = summary.sales_today?.total ?? 0;
  const salesTodayCount = summary.sales_today?.count ?? 0;
  const receivablesTotal = summary.receivables_total ?? 0;
  const payablesTotal = summary.payables_total ?? 0;
  const lowStockCount = summary.low_stock_count ?? 0;

  // Month revenue: query v_monthly_sales for the current local month.
  // Doing this server-side keeps the dashboard fully SSR.
  const monthRes = await supabase
    .from("v_monthly_sales")
    .select("revenue, local_month")
    .eq("shop_id", currentShop.id)
    .order("local_month", { ascending: false })
    .limit(1);
  const monthRevenue = Number(monthRes.data?.[0]?.revenue ?? 0);

  const money = (n: number) =>
    formatMoney(n, currentShop.currency_code, locale);

  const topCustomers: PartyBalance[] = receivableRows
    .slice(0, TOP_N)
    .map((r) => ({
      party_id: r.party_id,
      name: r.name,
      amount: Number(r.receivable ?? 0),
    }));
  const topSuppliers: PartyBalance[] = payableRows
    .slice(0, TOP_N)
    .map((r) => ({
      party_id: r.party_id,
      name: r.name,
      amount: Number(r.payable ?? 0),
    }));

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <h1 className="text-2xl font-semibold tracking-tight">
        {currentShop.name}
      </h1>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label={t("kpis.salesToday")}
          value={money(salesTodayTotal)}
          secondary={t("kpis.salesCount", { count: salesTodayCount })}
          icon={Receipt}
        />
        <KpiCard
          label={t("kpis.monthRevenue")}
          value={money(monthRevenue)}
          icon={TrendingUp}
        />
        <KpiCard
          label={t("kpis.receivables")}
          value={money(receivablesTotal)}
          icon={ArrowDownToLine}
        />
        <KpiCard
          label={t("kpis.payables")}
          value={money(payablesTotal)}
          icon={ArrowUpFromLine}
        />
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center gap-3">
          <Boxes
            className="size-5 text-muted-foreground"
            aria-hidden
          />
          <CardTitle className="text-sm font-medium">
            {t("kpis.lowStock")}
          </CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          <span className="text-2xl font-semibold">
            {formatCount(lowStockCount, locale)}
          </span>{" "}
          <span className="text-muted-foreground">
            {t("kpis.lowStockUnit", { count: lowStockCount })}
          </span>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <BalanceList
          title={t("topCustomers.title")}
          rows={topCustomers}
          emptyMessage={t("topCustomers.empty")}
          formatAmount={money}
          viewAllHref="/people"
          viewAllLabel={t("topCustomers.viewAll")}
        />
        <BalanceList
          title={t("topSuppliers.title")}
          rows={topSuppliers}
          emptyMessage={t("topSuppliers.empty")}
          formatAmount={money}
          viewAllHref="/people"
          viewAllLabel={t("topSuppliers.viewAll")}
        />
      </div>
    </div>
  );
}

async function NoShopEmpty() {
  const t = await getTranslations("overview.noShop");
  return (
    <div className="mx-auto max-w-md py-16 text-center">
      <h1 className="text-xl font-medium">{t("title")}</h1>
      <p className="mt-2 text-sm text-muted-foreground">{t("description")}</p>
    </div>
  );
}
