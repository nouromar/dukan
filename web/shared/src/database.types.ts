// Generated from the Supabase schema via `pnpm types:gen`.
//
// Regenerate after every migration:
//   1. Local stack:     pnpm types:gen:local   (requires `supabase start`)
//   2. Hosted project:  SUPABASE_PROJECT_ID=xxx pnpm types:gen:remote
//
// This file is checked in so portals don't need a live Supabase
// connection at build time. Drift between schema and types is caught
// at typecheck (and during code review).

// Placeholder until the first real generation. Once types:gen runs,
// this file will be overwritten with the full schema types and the
// `Database` export below becomes the real source of truth consumed
// by createSupabaseServerClient<Database>(...) etc.
export type Database = {
  public: {
    Tables: Record<string, never>;
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
  };
};
