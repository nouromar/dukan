// Top bar — shop switcher (#269), search (#271 / global), user menu.
// Server component so the user menu can read the session via
// createSupabaseServerClient without shipping the SDK to the client.

import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { UserMenu } from "@/components/shell/user-menu";

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
      <UserMenu />
    </header>
  );
}
