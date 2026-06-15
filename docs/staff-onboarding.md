# Staff onboarding

How an owner adds a cashier (or another owner) to a shop. The mechanism
also covers the very first sign-in for an org owner whose account was
pre-created on the platform.

## Principle

**No links, no SMS infrastructure, no "accept" step.** The owner adds a
contact (phone or email) to the shop's pending-invite list. The next
time that person signs in to the mobile app or the portal, their
membership is created automatically.

The owner's only obligation is to tell the staff member which
phone/email to log in with — via WhatsApp, in person, however they
already communicate. The platform doesn't try to be a messaging
provider.

## Flow

```
OWNER (web shop-admin portal)
  Setup → "Add staff" dialog
    contact: +252612345678  OR  cashier@example.com
    role:    Cashier (default) | Owner
    Save
  → portal calls create_shop_invite(shop_id, phone, email, role_code)
  → shop_invite row stored with accepted_at = NULL
  → owner messages the staff member on WhatsApp:
      "Log into Dukan with +252612345678 — you'll see the shop"

CASHIER (mobile or portal)
  Sign in normally with that phone or email
  → on session loaded:
        mobile:  AuthController._claimPendingInvitesSilently()
        portal:  getCurrentShop() → claim_pending_invites_for_me()
  → claim_pending_invites_for_me():
      reads auth.users.phone + auth.users.email for the current user
      finds any pending shop_invite rows where phone OR email matches
      creates shop_membership rows with the invite's role
      marks invites accepted (accepted_at, accepted_by_user_id)
      audit-logs each join with setup.staff.join
  → shop list refreshes with the newly-joined shop(s)
```

## Backend surface

### `shop_invite` (migrations `0054_admin_portal_prereqs.sql` + `0055_invite_email_and_autoclaim.sql`)

| column                | notes                                                    |
| --------------------- | -------------------------------------------------------- |
| `id`                  | uuid pk                                                  |
| `shop_id`             | fk shop, on delete cascade                               |
| `phone`               | nullable; E.164 format when set                          |
| `email`               | nullable; lowercased                                     |
| `role_code`           | `cashier` or `owner`                                     |
| `expires_at`          | default now + 7 days                                     |
| `accepted_at`         | null = pending; non-null = claimed                       |
| `accepted_by_user_id` | fk auth.users, set on claim                              |
| `created_by`          | fk auth.users; the owner who issued the invite           |

CHECK: exactly one of `(phone, email)` must be set per row.

Unique pending indexes:
- `(shop_id, phone) WHERE accepted_at IS NULL`
- `(shop_id, email) WHERE accepted_at IS NULL`

So re-adding the same contact for the same shop while a previous
invite is still pending **returns the existing invite id** (with
refreshed expiry) — never creates duplicates.

### `create_shop_invite(p_shop_id, p_phone, p_email, p_role_code)`

Owner-only (capability: `setup.staff.invite`). Called by the portal's
Setup → Add Staff dialog. Provide exactly one of `p_phone` / `p_email`.

Idempotent on `(shop_id, phone)` or `(shop_id, email)` for pending
invites. Audit-logs `setup.staff.invite`.

### `claim_pending_invites_for_me()` — the auto-claim path

Caller is any signed-in user. Reads the caller's `phone` and `email`
from `auth.users` (security definer for the cross-schema read).
Inserts `shop_membership` rows for every matching pending invite,
marks each invite accepted, audit-logs `setup.staff.join` with the
channel (`phone` vs `email`).

Returns the count of newly-created memberships (existing ones that
were merely reactivated don't count).

Called by:
- **Mobile** — `AuthController._claimPendingInvitesSilently()` runs
  on every session load (initial + each `onAuthStateChange` event
  with a non-null session) before `loadShops()`. The first
  `loadShops()` therefore picks up any freshly-joined shops without
  a follow-up refresh.
- **Web portal** — `getCurrentShop()` (the cached server helper in
  `web/shop-admin/src/lib/current-shop.ts`) calls it before the
  shop-list query. `React.cache` dedupes per request, so the RPC
  fires once per server-side render.

Both call sites swallow errors (claim failure shouldn't block
sign-in). The RPC is also idempotent + a no-op when nothing
matches, so calling it on every render / sign-in is cheap.

### `accept_shop_invite(invite_id)` (legacy)

Kept from `0054` for any future deep-link landing page. The auto-claim
path makes it redundant for the standard flow — no UI calls it today.

## Permissions

- Issuing invites: capability `setup.staff.invite` — owner role only
  in v1 (`org_owner` does not inherit shop-level capabilities; one of
  the shop's `shop_role='owner'` members must do it).
- Claiming: any signed-in user, but the RPC restricts itself to
  invites whose phone/email matches `auth.users` for the current user.

## Failure modes + behavior

| Situation                                  | What happens                                |
| ------------------------------------------ | ------------------------------------------- |
| Owner adds same contact twice              | Returns the existing invite id (refreshed). |
| Cashier doesn't sign in for a while        | Invite waits, claimed on first sign-in.     |
| Cashier signs in 8+ days later             | Invite expired; claim ignores it.           |
| Owner removes pending invite (future UI)   | Mobile auto-claim finds nothing; no harm.   |
| Cashier already a member of the shop       | `on conflict (shop_id, user_id) do update`  |
|                                            | reactivates the membership.                 |
| Network failure during claim               | Swallowed; user can retry by reopening app. |

## User display name

`public.user_profile` (migration `0057_user_profile.sql`) stores a
free-form `display_name` per user. RLS: self-edit + read access shared
with anyone the viewer co-owns a `shop_membership` row with. The
portal's `/setup` page has a **My profile** card at the top where each
user sets their own name; the staff list and audit log render that
name in place of the UUID prefix when one is set.

There's no UI to set someone else's name — a user picks their own
display name and it shows up everywhere they're visible. Mobile profile
edit is deferred; mobile users without a display name show as "Unnamed"
+ UUID prefix on the portal until they sign in to the portal once and
set it (or until we ship the mobile profile edit screen).

## Testing

`scripts/test-backend-migrations.sh` (sections 4 / 4b / 4c / 4d):
- Cashier denied at create_shop_invite (capability gate).
- Owner happy path: phone variant + idempotent.
- Owner happy path: email variant + idempotent + reject both-set.
- claim_pending_invites_for_me: claims both a phone- and email-keyed
  invite for the same user, creates a single membership, marks
  both invites accepted, writes two `setup.staff.join` audit rows,
  re-claim returns 0.

Mobile + portal sides currently rely on the harness for the
backend contract and on manual testing for the UI wiring.
