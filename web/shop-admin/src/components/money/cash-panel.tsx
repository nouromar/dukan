// Cash position card for the Money module. Renders the three numbers
// from v_cash_position: in, out, net. Sign-tinted net.

import { useTranslations } from "next-intl";
import { formatMoney } from "shared";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/data-table";
import { cn } from "@/lib/utils";

export type CashPosition = {
  cash_in: number;
  cash_out: number;
  cash_balance: number;
};

export function CashPanel({
  position,
  currencyCode,
  locale,
}: {
  position: CashPosition | null;
  currencyCode: string;
  locale: string;
}) {
  const t = useTranslations("money.cash");
  const money = (n: number) => formatMoney(n, currencyCode, locale);

  if (
    !position ||
    (position.cash_in === 0 && position.cash_out === 0)
  ) {
    return (
      <EmptyState
        title={t("empty.title")}
        description={t("empty.description")}
      />
    );
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Card>
          <CardContent className="space-y-1 pt-6">
            <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("kpis.in")}
            </div>
            <div className="text-2xl font-semibold tabular-nums text-emerald-700 dark:text-emerald-400">
              {money(position.cash_in)}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="space-y-1 pt-6">
            <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("kpis.out")}
            </div>
            <div className="text-2xl font-semibold tabular-nums text-amber-700 dark:text-amber-400">
              {money(position.cash_out)}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="space-y-1 pt-6">
            <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {t("kpis.balance")}
            </div>
            <div
              className={cn(
                "text-3xl font-semibold tabular-nums",
                position.cash_balance < 0
                  ? "text-destructive"
                  : position.cash_balance > 0
                    ? "text-emerald-700 dark:text-emerald-400"
                    : "text-muted-foreground",
              )}
            >
              {money(position.cash_balance)}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
