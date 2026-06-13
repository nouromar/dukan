# Dukan — Shop Admin Portal

Back-office web portal for the **business that owns the shop** — organization owners running multiple shops, single-shop owners doing month-end work, bookkeepers preparing exports. Daily transactional work lives in the mobile app at `app/dukan/`; this portal is for the analytical / bulk / reporting work that mobile is the wrong tool for.

Target state: `docs/shop-admin-portal.md`.
Current punch list: `docs/shop-admin-portal-alignment.md`.

## Stack

- Next.js 16 (App Router) + React 19
- TypeScript strict
- Tailwind CSS v4
- shadcn/ui (Radix primitives + Lucide icons)
- Supabase JS client (auth + RPC + Realtime) — wired in #268
- next-intl for English + Somali — wired in #270
- TanStack Table v8 for module tables — wired in #271

## Local development

From the **monorepo root**:

```bash
pnpm install                                    # once
pnpm --filter shop-admin dev                    # http://localhost:3000
pnpm --filter shop-admin typecheck              # tsc --noEmit
pnpm --filter shop-admin lint
pnpm --filter shop-admin build                  # production build
```

The portal expects:

- `NEXT_PUBLIC_SUPABASE_URL` — local stack `http://127.0.0.1:54321` or your hosted Supabase URL.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — the publishable anon key.

Copy `.env.example` (created in #268) to `.env.local` and fill them in.

## Layout

```
src/
├── app/
│   ├── layout.tsx           Root layout (TooltipProvider, Toaster, fonts)
│   ├── page.tsx             /  → redirects to /overview
│   ├── globals.css          Tailwind v4 imports + shadcn theme tokens + Dukan brand color
│   └── (dashboard)/
│       ├── layout.tsx       Persistent left rail + top bar
│       ├── overview/page.tsx        #274 — single-shop dashboard
│       ├── sales/page.tsx           #275 — sales history
│       ├── inventory/page.tsx       #278 — products table
│       ├── people/page.tsx          #280 — customers + suppliers
│       ├── money/page.tsx           (P1)
│       ├── setup/page.tsx           (P1)
│       └── audit/page.tsx           #283 — audit log feed
├── components/
│   ├── shell/
│   │   ├── left-rail.tsx          Persistent navigation
│   │   ├── top-bar.tsx            Shop switcher + search + user menu (placeholders)
│   │   └── module-placeholder.tsx Shared "scaffolded, not implemented" card
│   └── ui/                        shadcn primitives
└── lib/
    └── utils.ts                   cn() helper
```

## What's intentionally NOT here

Per `docs/shop-admin-portal.md` § 20: posting paths (sales/receives/payments — those originate on mobile), platform-level data, user impersonation, hardware register integration. Two narrow posting exceptions are documented in design § 7: stock adjustments and cash-reconciliation correction.
