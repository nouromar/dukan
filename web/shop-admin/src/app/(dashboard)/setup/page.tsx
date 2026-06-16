// The Setup index redirects to its first tab so we have a single
// canonical URL per panel (no "what does /setup show?" ambiguity).

import { redirect } from "next/navigation";

export default function SetupIndex() {
  redirect("/setup/general");
}
