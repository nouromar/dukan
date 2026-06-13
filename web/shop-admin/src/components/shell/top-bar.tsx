// Top bar — shop switcher + search + user menu. All three are
// placeholders until #269 (shop switcher), #271 (search), and #268
// (user menu after auth lands).

import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";

export function TopBar() {
  return (
    <header className="flex h-14 items-center gap-4 border-b bg-background px-6">
      <div className="text-sm text-muted-foreground">All shops</div>
      <div className="relative ml-auto w-full max-w-sm">
        <Search
          className="pointer-events-none absolute left-2.5 top-2.5 size-4 text-muted-foreground"
          aria-hidden
        />
        <Input
          type="search"
          placeholder="Search products, parties, invoices…"
          className="pl-8"
          disabled
          aria-label="Search"
        />
      </div>
      <div className="text-sm text-muted-foreground">Signed out</div>
    </header>
  );
}
