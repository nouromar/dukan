import { redirect } from "next/navigation";

export default function RootPage() {
  // Auth middleware (#268) will redirect unauthenticated users to /login
  // before this even runs. For now the root just routes into the dashboard.
  redirect("/overview");
}
