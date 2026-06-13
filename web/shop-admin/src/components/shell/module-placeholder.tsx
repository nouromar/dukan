// Shared placeholder rendered by every module's index page until the
// real content lands. Lets us scaffold the full nav surface first and
// fill in one module at a time without empty-route 404s.

import { Construction } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export type ModuleKey =
  | "overview"
  | "sales"
  | "inventory"
  | "people"
  | "money"
  | "setup"
  | "audit";

export async function ModulePlaceholder({
  module,
  task,
}: {
  module: ModuleKey;
  task: string;
}) {
  const tNav = await getTranslations("nav");
  const tPlaceholder = await getTranslations("modulePlaceholder");
  return (
    <div className="mx-auto max-w-2xl py-12">
      <div className="mb-6 flex items-center gap-3">
        <Construction className="size-6 text-muted-foreground" aria-hidden />
        <h1 className="text-2xl font-semibold tracking-tight">
          {tNav(module)}
        </h1>
      </div>
      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium text-muted-foreground">
            {tPlaceholder(module)}
          </CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          {tPlaceholder("notImplemented", { task })}
        </CardContent>
      </Card>
    </div>
  );
}
