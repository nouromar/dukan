// Client wrapper for the two People tabs. Lives on the client because
// Tabs is a client component; the actual data was fetched server-side
// in /people/page.tsx and handed in as props.

"use client";

import { useTranslations } from "next-intl";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { PartiesTable, type Party } from "./parties-table";

export function PeopleTabs({
  customers,
  suppliers,
  currencyCode,
  locale,
}: {
  customers: Party[];
  suppliers: Party[];
  currencyCode: string;
  locale: string;
}) {
  const t = useTranslations("people");
  return (
    <Tabs defaultValue="customers" className="w-full">
      <TabsList>
        <TabsTrigger value="customers">
          {t("tabCustomers")} ({customers.length})
        </TabsTrigger>
        <TabsTrigger value="suppliers">
          {t("tabSuppliers")} ({suppliers.length})
        </TabsTrigger>
      </TabsList>
      <TabsContent value="customers" className="mt-4">
        <PartiesTable
          kind="customers"
          rows={customers}
          currencyCode={currencyCode}
          locale={locale}
        />
      </TabsContent>
      <TabsContent value="suppliers" className="mt-4">
        <PartiesTable
          kind="suppliers"
          rows={suppliers}
          currencyCode={currencyCode}
          locale={locale}
        />
      </TabsContent>
    </Tabs>
  );
}
