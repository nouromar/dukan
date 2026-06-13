import { User as UserIcon } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { buttonVariants } from "@/components/ui/button";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";

export async function UserMenu() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const phone = user?.phone ?? "—";
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          buttonVariants({ variant: "ghost", size: "sm" }),
          "gap-2",
        )}
      >
        <UserIcon className="size-4" aria-hidden />
        <span className="max-w-[140px] truncate text-sm">{phone}</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48">
        <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">
          Signed in as
        </DropdownMenuLabel>
        <DropdownMenuLabel className="pt-0 text-sm">{phone}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem>
          <form action="/auth/signout" method="post" className="w-full">
            <button type="submit" className="w-full text-left">
              Sign out
            </button>
          </form>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
