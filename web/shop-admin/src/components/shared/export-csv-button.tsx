// Generic "Export CSV" button used by every module. Renders as an
// outline button with a download icon; clicking it triggers a real
// browser file download via a hidden <a download> click.
//
// We bypass Server Actions for the actual download because Actions
// return serializable values, not Response streams. A Route Handler
// (one per module) returns the CSV body with the right headers; this
// component just opens it.

"use client";

import { useTransition } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { Download } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export function ExportCsvButton({ href }: { href: string }) {
  const t = useTranslations("export");
  const [pending] = useTransition();
  return (
    <Link
      href={href}
      // Hint to the browser: treat as attachment; server already
      // sets Content-Disposition. Keeps the link clickable in new
      // tabs without losing the download semantics.
      target="_blank"
      rel="noopener"
      className={cn(
        buttonVariants({ variant: "outline", size: "sm" }),
        "gap-2",
      )}
    >
      <Download className="size-4" aria-hidden />
      {pending ? t("exporting") : t("button")}
    </Link>
  );
}
