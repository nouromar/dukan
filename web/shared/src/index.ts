// Cross-portal shared TypeScript surface.
//
// What lives here:
//   - database.types.ts    Generated from Supabase via `supabase gen types`.
//                          Source of truth for row shapes consumed by
//                          web/shop-admin and (future) web/system-admin.
//   - config.ts            Business-rule constants mirrored from
//                          app/dukan/lib/config/business_rules.dart.
//                          Mobile + web must agree on void windows,
//                          country code default, etc.
//
// What doesn't:
//   - React components — those live in their portal package.
//   - Server logic — those are Supabase Edge Functions under
//     supabase/functions/.
//
// Importable as `from 'shared'` from any web/* workspace member.

export * from './config';
export * from './currency';
