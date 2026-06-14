// Top-5 party balances card. Used twice on the Overview: once for
// customers (receivables) and once for suppliers (payables). The
// only thing that differs between the two is title + balance column,
// so the card takes them as props.

import Link from "next/link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export type PartyBalance = {
  party_id: string;
  name: string;
  amount: number;
};

export function BalanceList({
  title,
  rows,
  emptyMessage,
  formatAmount,
  viewAllHref,
  viewAllLabel,
}: {
  title: string;
  rows: PartyBalance[];
  emptyMessage: string;
  formatAmount: (n: number) => string;
  viewAllHref: string;
  viewAllLabel: string;
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        <Link
          href={viewAllHref}
          className="text-xs font-medium text-primary hover:underline"
        >
          {viewAllLabel} →
        </Link>
      </CardHeader>
      <CardContent>
        {rows.length === 0 ? (
          <p className="py-4 text-sm text-muted-foreground">{emptyMessage}</p>
        ) : (
          <ul className="divide-y">
            {rows.map((row) => (
              <li
                key={row.party_id}
                className="flex items-center justify-between py-2.5 text-sm"
              >
                <span className="truncate">{row.name}</span>
                <span className="font-medium tabular-nums">
                  {formatAmount(row.amount)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
