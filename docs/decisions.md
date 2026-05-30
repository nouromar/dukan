# Dukan — Open Questions: Decisions & Recommendations

> **Status:** Pending review. Each recommendation is the research sub-agent's best synthesis of available evidence. Mark each as ACCEPTED / MODIFIED / REJECTED before Phase 1 schema work begins.
>
> **Sources:** Supabase docs, Wikipedia (Hormuud, Telesom, Golis, Somali Shilling, Telecommunications in Somalia, SEACOM), DataReportal Digital 2024 & 2026 Somalia reports, plan.md, architecture.md, ux.md.

---

## Summary Table

| # | Question | Recommended Answer | Confidence |
|---|---|---|---|
| 1 | Auth method | **Phone OTP via Twilio** (primary) + **WhatsApp OTP** (fallback A) + **invite-code** (fallback B for concierge onboarding) | Low — must test in-country |
| 2 | Pilot currency | **USD as default** (DECIDED 2026-05-29 by @nouromar). SLSH supported for Hargeisa shops; SOS not in v1 unless a pilot shop specifically requests it. | DECIDED |
| 3 | Supabase region | **eu-central-1 (Frankfurt)**, validate with real-device latency test | Medium |
| 4 | Roles for v1 | **Owner + Cashier only**; Manager & Viewer seeded in reference table, not surfaced in UI | High |
| 5 | Receipt printer | **Defer to post-pilot**; design printable render layer now as a hook | High |
| 6 | SMS/WhatsApp receipt sharing | **Defer to post-pilot**; share hook in transaction render already in plan | High |
| 7 | Cost capture on bono | **Confirm plan**: unit-cost ↔ line-total toggle; no discount fields or taxes in v1 | High |
| 8 | Sales pricing model | **Confirm plan**: price defaults from item, override via long-press; no fixed-price enforcement | High |
| 9 | Costing policy | **Confirm plan**: weighted-average at receive posting + COGS snapshotted on sale line | High |
| 10 | Data export & admin recovery | **CSV export** (items + transactions + lines) + **owner self-service void** (≤7 days). **Support is setup-only — cannot post voids or any transactional changes** (DECIDED 2026-05-29 by @nouromar). | DECIDED |

---

## Question 1 — Auth Method

### Options

| Option | Mechanism | Supabase support? |
|---|---|---|
| A | Phone OTP via SMS (Twilio) | ✅ native |
| B | Phone OTP via SMS (Vonage / Nexmo) | ✅ native |
| C | Phone OTP via SMS (MessageBird / Bird) | ✅ native |
| D | Phone OTP via SMS (TextLocal) | ✅ community-supported |
| E | Phone OTP via SMS (Africa's Talking) | ⚠️ custom — via Edge Function wrapping AT API |
| F | WhatsApp OTP (Twilio Verify WhatsApp channel) | ✅ native — Supabase supports WhatsApp OTP via Twilio |
| G | Email OTP | ✅ native (Supabase built-in) |
| H | Invite code / owner-issued 6-digit code | 🔧 custom (no 3rd-party delivery) |

### Evidence

**Somalia telecom landscape:**
- **Hormuud Telecom** (Mogadishu / south Somalia): largest operator, 3.6M+ customers, GSM/3G/4G/5G, prefix +252 61/62. Operates EVC Plus mobile money and WAAFI super-app (2024). ISO-certified, internationally recognized.
- **Telesom** (Hargeisa / Somaliland): dominant in Somaliland region; 2G/3G/LTE; ZAAD mobile money service (USD-denominated). Prefix +252 63.
- **Golis Telecom** (Bosaso / Puntland): 2G/3G; covers 50+ districts in Puntland; SAHAL mobile money (licensed 2023). Prefix +252 90.
- **Somtel** (nationwide, Dahabshiil-owned): broadband and mobile; prefix +252 68.
- Interconnection: Hormuud, NationLink, and Somtel formed the **Somali Telecommunication Company (STC)** in 2014 for cross-network calls. Golis joined NCA's interconnection framework in 2022.
- All operators use GSM standard (2G minimum), which is compatible with international A2P SMS routing over SS7/SMPP.

**Mobile and internet penetration (DataReportal Digital 2026, data as of Oct 2025):**
- 11.5 million active mobile connections (58.1% of population)
- 5.47 million internet users (27.6%)
- 3.51 million social media user identities
- 75.7% of mobile connections are 3G/4G/5G ("broadband")
- Mobile connection count significantly exceeds internet users → phone number is far more universal than email address for this audience.

**Supabase SMS providers:**
- Supabase Auth supports Twilio, Vonage, MessageBird (now Bird), and TextLocal as SMS providers ([supabase.com/docs/guides/auth/phone-login](https://supabase.com/docs/guides/auth/phone-login)).
- OTP default: one request per 60 seconds, expires in 1 hour. Both defaults can be configured.
- WhatsApp OTP is also supported through Twilio's Verify product.

**SMS deliverability to Somalia — what we know:**
- Twilio claims 180+ countries; Vonage claims global coverage. Neither explicitly lists Somalia in public documentation scraped during this research.
- Somalia has no international SMS regulations that would block A2P messages (unlike some countries that require sender registration).
- The main risk is not regulatory but **routing quality**: international SMS aggregators reach Somalia via their hub networks but last-mile delivery through Hormuud/Telesom/Golis depends on roaming/interconnection agreements. This is opaque without testing.
- **Africa's Talking** (Kenya-based aggregator, widely used for East Africa) claims coverage in 40+ African countries and is commonly cited for Somalia in developer communities. It can be integrated via a custom SMS Edge Function (Supabase does not natively list AT as a provider, but this is straightforward to wrap).
- Cost estimate for A2P SMS to Somalia: typically **$0.05–$0.15/message** via Twilio or Vonage for African destinations (exact Somalia rate requires account-level quote; high African rates are well-documented).
- For a pilot of ≤50 shops: cost is negligible if OTP is the only SMS use.

**WhatsApp as channel:**
- WhatsApp is widely used in Somalia. DataReportal 2026 shows 3.51M social media identities; Hormuud's own WAAFI app includes WhatsApp-style messaging, indicating smartphone and OTT-app familiarity.
- Twilio Verify supports WhatsApp OTP natively, and Supabase's phone login can be configured to deliver via WhatsApp through Twilio.
- WhatsApp OTP is more reliable than SMS in markets where international SMS routing is weak, because WhatsApp uses data (app-to-app) rather than the SS7 voice/SMS network.
- Prerequisite: user must have WhatsApp installed and an active data connection.

**Email OTP:**
- Email ownership in Somalia is low for the target audience (small shopkeepers). Not practical as primary or even fallback. Ruled out.

**Invite codes:**
- Later decision: v1 disables in-app support codes. For concierge onboarding, support staff may still create the account in Supabase and share a one-time login link or temporary login credential via phone/WhatsApp out-of-band; this is not the same as owner-granted support access.
- Zero delivery risk. Perfect for the pilot where every user is onboarded with support involvement anyway.
- Downside: does not scale to self-service signup.

### Recommendation

**Primary:** Phone OTP via **Twilio** (simplest integration with Supabase; widest coverage claims). Extend the OTP expiry from 60 seconds to **5 minutes** for the pilot (configurable in Supabase Auth settings) — 60 seconds is tight for a user who may need to switch apps or have slow SMS delivery.

**Fallback A:** **WhatsApp OTP** via Twilio Verify. Configure as automatic fallback when SMS fails (Twilio Verify handles this automatically). For smartphone-using shopkeepers with WhatsApp (likely majority of pilot users given 4G penetration), this is more reliable than SMS routing.

**Fallback B:** **Invite-code + support-seeded account** for the concierge-onboarding path. Since every pilot shop is onboarded with support involvement, the first login can use a temporary password or magic link delivered out-of-band (e.g., support staff reads or shares a link via WhatsApp). Phone OTP takes over for subsequent logins once the account exists.

**Do not use:** Email OTP. The audience does not have reliable email.

**Africa's Talking as alternative aggregator:** If Twilio shows poor deliverability to Hormuud/Golis in initial testing, Africa's Talking is the fallback SMS aggregator. Integration requires a small Edge Function wrapper; ~1 day of work.

**Critical pre-pilot action:** Before Phase 1 schema is final, send **10 test SMS messages to real Hormuud, Telesom, Golis, and Somtel numbers** using Twilio and/or Africa's Talking. Record delivery rate and latency. If < 90% in under 2 minutes, switch to WhatsApp OTP as primary.

### Confidence: **Low**
The technical path is clear, but actual Somalia SMS deliverability from Twilio/Vonage is **unverified from public sources**. This is the highest-risk decision in the list because a failed auth method blocks the entire pilot.

### Implication if Wrong
If SMS OTP fails (say 40% delivery rate to Hormuud numbers), users cannot log in. Fallback to invite-code still works for the pilot but removes self-service signup capability entirely. Must be tested before Phase 1 is complete, not after.

---

## Question 2 — Currency for Pilot

### Options

| Option | Description |
|---|---|
| A | USD only (enforced default, no choice) |
| B | SOS (Somali Shilling) only |
| C | SLSH (Somaliland Shilling) only |
| D | Shop-choice at setup — but default to USD |
| E | Shop-choice at setup — default to SOS |

### Evidence

**USD dominance in Somali commerce:**
- Wikipedia (Somali Shilling): *"The United States dollar is still the main currency used in Somalia, with it being most prolific in electronic payments using SMS like EVC Plus."*
- Wikipedia (Somali Shilling): *"Owing to a lack of confidence in the Somali shilling, the U.S. dollar was widely accepted as a medium of exchange alongside the Somali shilling."*
- Exchange rate history: SOS has been volatile since the civil war; as of May 2025: ~**26,000 SOS/USD**.
- **Mobile money is USD-denominated:** Hormuud EVC Plus, Telesom ZAAD, and Golis SAHAL all operate in USD. This means digitally-inclined shopkeepers already think in USD for financial tracking.

**Mogadishu shops (April 2026 data point):**
- Wikipedia notes that in April 2026, *"many businesses and shops stopped accepting shillings due to them being in very poor quality due to their age"* and adopted mobile phone payments. This is a strong signal that USD is increasingly the de-facto trading currency even for small shops in Mogadishu.

**Hargeisa / Somaliland:**
- Telesom is dominant. ZAAD (USD) is the standard mobile money.
- **Somaliland Shilling (SLSH)** is a separate unofficial currency used in Somaliland with its own exchange rate (~9,000–10,000 SLSH/USD as of 2024). This is distinct from SOS.
- Hargeisa shops may price in USD, SLSH, or both. USD is widely accepted.

**SOS practical problem for a shop app:**
- Prices in SOS are large 5-digit integers (e.g., a 25 kg bag of rice = ~500,000–700,000 SOS). The numeric keypad UX would need to handle very large numbers, increasing tap count and mis-entry risk.
- Inflation risk: SOS value can change 10–30% in a year, making the "default price" on items stale quickly.

**Architecture note:**
- The plan already mandates one currency per shop for v1, with `currency_code` set at shop creation. The `currencies` reference table already seeds USD, SOS, etc. The only decision is what the default is and whether to offer SOS as a pilot option.

### Recommendation

**Default currency for new pilot shops: USD.**

- This aligns with the dominant digital commerce currency in Somalia.
- It avoids large-integer UX problems.
- Mobile money (EVC Plus, ZAAD) is USD-denominated; shopkeepers reconciling against these platforms will find USD natural.
- **Seed SLSH** (Somaliland Shilling) in the currencies reference table from day one, so Hargeisa pilot shops can select it. SLSH requires: symbol, decimals=2, approximate rate context. Do not build a live exchange rate feed; rates are entered manually in the shop template.
- **Do not default to SOS** for the pilot. Even shops that use SOS for cash transactions likely use USD as their mental unit-of-account for stock costing (because bonos from wholesalers are often in USD).
- After pilot: if shops strongly prefer SOS, it is a one-line change to the seed data and a support team operation to update existing shops' currency setting.

**What "one currency per shop" means operationally:**
- Shop setup screen shows: "Your shop's currency" → dropdown with USD pre-selected (can change to SLSH or SOS if needed).
- All prices, costs, and totals are stored and displayed in the shop's chosen currency.
- No mixed-currency support in v1.

### Confidence: **Medium-High**
Strong evidence from Wikipedia, mobile money platforms, and Mogadishu market behavior that USD is the right default. Uncertainty remains for smaller towns and rural areas where SOS cash may still dominate. The shop-choice architecture means the default can be overridden by support staff at setup with zero code change.

### Implication if Wrong
If shopkeepers consistently use SOS for pricing, they'll enter huge numbers (50,000–700,000 range) and the numeric pad UX will feel cumbersome. Fixable by either switching the shop's currency setting or by improving the large-number UX (thousands-separator auto-input). Not a schema change.

---

## Question 3 — Supabase Region

### Options

| Region | AWS code | Distance from Somalia | Notes |
|---|---|---|---|
| Frankfurt | eu-central-1 | ~5,500 km (cable) | SEACOM cable has Frankfurt PoP |
| London | eu-west-2 | ~6,000 km (cable) | SEACOM has London/Slough PoP |
| Mumbai | ap-south-1 | ~3,800 km (cable) | Djibouti → India submarine cable (shorter path) |
| Ireland | eu-west-1 | ~7,000 km | No direct cable advantage |
| Bahrain / UAE | me-south-1 | ~2,000 km | **Not available on Supabase** |

### Evidence

**Supabase available regions (from [supabase.com/docs/guides/platform/regions](https://supabase.com/docs/guides/platform/regions)):**
Supabase supports the following relevant regions: `eu-central-1` (Frankfurt), `eu-west-2` (London), `ap-south-1` (Mumbai). There is **no Middle East (me-south-1 Bahrain or me-central-1 UAE) region** on Supabase as of 2025.

**Internet routing from Somalia:**
- Somalia's international internet egress runs primarily through **Djibouti**, which is East Africa's major submarine cable hub.
- Key submarine cables landing in/near Djibouti: **SEACOM** (to Europe via Marseille/Frankfurt/London), **EASSy** (East Africa Submarine System, to Europe and the US), **AAE-1** (Asia–Africa–Europe 1, connects to UAE/India/Europe).
- **SEACOM** explicitly operates PoPs in Amsterdam, Frankfurt, London, Marseille, and Slough (UK). Frankfurt is one of SEACOM's named PoPs, making it the most direct cable route to a Supabase data center.
- **Mumbai (ap-south-1):** The cable distance from Djibouti to Mumbai is shorter than to Frankfurt (~3,800 km vs ~5,500 km), and AAE-1 connects Djibouti directly to India. However, routing hops and peering relationships may or may not favor Mumbai in practice.
- Estimated latency Somalia → Frankfurt: ~120–180 ms RTT (based on cable distance at ~200 km/ms in fiber + routing overhead).
- Estimated latency Somalia → Mumbai: ~100–150 ms RTT.
- DataReportal 2024: median mobile internet speed in Somalia = **14.88 Mbps**; median fixed speed = **19.14 Mbps** (2025). These are sufficient speeds — latency (RTT), not throughput, is the binding constraint for an HTTPS/REST app.

**Data residency considerations:**
- Somalia has no data protection law requiring data localization as of 2025. The National Communications Act (2017) governs telecoms, not data residency.
- No legal requirement to store data in-country or in Africa. Choose on pure performance grounds.

**Supabase note:** Supabase does not yet support general regions for read replicas or management API. For a single-region v1 project, this is irrelevant.

### Recommendation

**Primary: `eu-central-1` (Frankfurt).**

Rationale:
- SEACOM submarine cable explicitly has a Frankfurt PoP, making it the most direct cable path from East Africa.
- Frankfurt is Europe's largest internet exchange (DE-CIX), meaning low latency to the Supabase infrastructure.
- Well-tested path for many African SaaS products.

**Alternative to test: `ap-south-1` (Mumbai).**
Mumbai may actually have lower latency than Frankfurt for Mogadishu (shorter cable distance via Djibouti–India path). If real-device testing shows Mumbai RTT < Frankfurt RTT by > 20 ms, switch before pilot launch.

**Mandatory pre-pilot action:** Before committing, run `ping`/HTTP round-trip tests from an Android device on Hormuud 4G in Mogadishu and Telesom 4G in Hargeisa to the Supabase URLs for both `eu-central-1` and `ap-south-1` projects. Use the lower-latency region. This test costs under $50 in data fees for a local tester and takes 30 minutes.

**Architecture implication:** Region is selected at Supabase project creation and cannot be changed post-creation without a full data migration. Make this decision before Phase 1 provisions the project.

### Confidence: **Medium**
The SEACOM-to-Frankfurt path is well-supported by cable topology. Mumbai is a credible alternative. Without real device testing from Somalia, this remains an educated estimate.

### Implication if Wrong
If wrong region chosen: 50–100 ms extra RTT on every API call. For a sale flow targeting ≤5 seconds, this adds up (5–10 round-trips per sale = 250–1000 ms extra latency). Not catastrophic but measurable. Fixable only by migrating the Supabase project (pg_dump → restore → re-provision), which is feasible but painful. **Worth spending 1 day testing before provisioning.**

---

## Question 4 — Roles for v1

### Options

| Option | Roles |
|---|---|
| A | Owner only |
| B | Owner + Cashier |
| C | Owner + Cashier + Manager |
| D | Owner + Manager + Cashier + Viewer |

### Evidence

**Plan scope:**
- `plan.md` §8 lists Owner/Manager/Cashier/Viewer as a question to confirm.
- `architecture.md` schema has `user_role(id pk, code)` as a reference table, seeded with these values.
- Roles gating: `membership.role_id` checked in RLS policies; architecture.md notes "Only roles 'owner' and 'manager' may post voids/refunds (enforced by RLS)."

**Pilot shop reality:**
- Target: small one- or two-person neighbourhood shops (dukaan).
- Most common structures: (a) sole owner runs everything; (b) owner + 1 cashier at the counter; (c) owner + family member.
- **Manager** role adds value when: owner is absent, delegate needs to receive goods (creates payables), void transactions, or edit prices. For a 2-person shop, the owner is the manager. For a 3+ person shop, there might be a trusted senior employee.
- **Viewer** adds value when: owner has an external investor or spouse who wants to view reports but not edit data. This is a real use case but low priority for a pilot.
- For a 5–20 shop pilot, the vast majority will run as Owner-only or Owner+Cashier.

**What Cashier can and cannot do (proposed):**
- CAN: post Sales (cash and debt), view their own today's summary.
- CANNOT: void/reverse any transaction, receive goods (Receive flow), record payments, access financial reports, change settings, change item prices.
- **Edge case**: can Cashier override a price? Recommendation: NO in v1. Price override is a long-press power-user action that requires Owner role. If this causes friction in testing, add a configurable "allow cashier price override within X%" setting at setup (v2).

**Manager vs Cashier:**
- Manager would add: can Receive goods, can make payments, can void within a time window, cannot change settings or user roles. This is genuinely useful for a 3-person shop but adds non-trivial RLS policy complexity.

### Recommendation

**v1 pilot: Owner + Cashier only.**

- Seed `Manager` and `Viewer` in the `user_role` reference table (with `ref_translation` rows for en + so) — zero schema cost, done at seed time.
- Do not build any Manager-specific RLS policies or UI for v1.
- Expose only Owner and Cashier in the "Add team member" UI.
- Owner: all permissions.
- Cashier: can post Sales; everything else blocked.

**Practical implication:** If a pilot shop has a "manager" who needs to receive goods, onboard them as Owner for the pilot (we can distinguish them later). This is a concession, not a design flaw.

**When Manager becomes needed:** When a pilot shop wants to delegate Receive and Payment flows without giving full Owner access. Likely first raised during pilot feedback, not before.

### Confidence: **High**

### Implication if Wrong
If some pilot shops have 3-person structures needing Manager capabilities, they'll use Owner accounts for the extra person. This gives them too many permissions but doesn't break the pilot. The schema already supports a clean upgrade path to Manager in v2.

---

## Question 5 — Receipt Printer at Point of Sale

### Options

| Option | |
|---|---|
| A | Bluetooth thermal printer support in v1 |
| B | Defer to post-pilot |

### Evidence

**Market evidence for small Somali shops:**
- No documented evidence of Bluetooth thermal printer adoption in typical Somali neighbourhood shops. Traditional practice: hand-written receipts (Somali: "kabaal" / "rasiiid") or no receipt given.
- Somalia's commerce is heavily mobile-money-based (EVC Plus, ZAAD, SAHAL). These platforms send SMS confirmations to both parties — the "receipt" is the SMS confirmation, not a paper slip.
- Hormuud's WAAFI app and Telesom's ZAAD service generate digital transaction records; shopkeepers accustomed to these may have no expectation of paper receipts.
- Bluetooth thermal printers ($40–80 via AliExpress or regional distributors) are available in East Africa but primarily adopted by formal restaurants, pharmacies, and petrol stations — not small neighbourhood general stores.
- Adding printer support requires: Bluetooth permission handling (Android/iOS), ESC/POS command formatting, printer pairing UX, paper width/font configuration, and testing across multiple printer models (Goojprt, EPSON, Star, etc.). Significant dev effort.
- The plan already lists hardware integrations (printers, scanners, drawers) as explicitly **out of v1** (`plan.md §7a`).

**What to build instead:**
- Design the transaction confirmation screen as a structured "receipt view" (shop name, date, items, total, payment method) — this costs nothing extra and is needed for the summary screen anyway.
- Add a "share receipt" action slot (as a disabled/hidden button) on the transaction detail screen. When printer support is added in v2, it plugs directly into this slot.

### Recommendation

**Defer to post-pilot.** Do not include Bluetooth printer support in v1.

Design the transaction detail screen with a clean receipt-formatted layout now. This serves as the in-app receipt view and is the hook for future print/share functionality.

**Revisit signal:** If ≥ 30% of pilot shop owners spontaneously ask "can I print receipts?" in usability testing or support sessions, move to v2 priority. Until then, it is not a felt need.

### Confidence: **High**

### Implication if Wrong
If shopkeepers strongly want paper receipts, they continue writing them by hand (current practice). App adoption is not blocked. Worst case: a few pilot shops use the app only for inventory/reports and continue manual receipts for customers — still better than nothing.

---

## Question 6 — SMS / WhatsApp Sharing of Receipts to Customers

### Options

| Option | |
|---|---|
| A | Include in v1 |
| B | Defer to post-pilot |

### Evidence

**Felt need signal:**
- Somali business-to-customer communication already happens organically via WhatsApp. Shopkeepers already send informal "your balance is X" messages via WhatsApp — this is not a gap the app uniquely fills in v1.
- No evidence from the plan docs or UX research of shopkeepers specifically requesting digital receipt sharing.

**UX cost:**
- Adding a "Send receipt to customer" action to the sale confirmation flow introduces an extra decision point into what must be a ≤5-second flow.
- If made optional: adds a tap for users who don't want it. If made mandatory: breaks the speed contract.
- If made post-sale (available from transaction history): lower UX cost but removes the immediacy.

**Technical cost:**
- WhatsApp Business API: requires Meta business verification + approved message templates + ~$0.05–0.10/message for utility-category messages. Not trivial to set up, and adds ongoing operational cost.
- SMS: additional cost per message; requires phone number capture for every customer (currently only required for debt sales).

**Architecture note:**
- `plan.md §7a` already calls this out: "design transaction render so a 'share' hook can attach later."
- No schema changes needed. The hook is: render transaction as a shareable text or structured message; expose a "Share" action on the transaction detail screen.

### Recommendation

**Defer to post-pilot.** Include the "Share receipt" action slot (visually present, functionally disabled or hidden) in the transaction detail screen. Do not implement delivery logic in v1.

**Decision trigger for v2:** If pilot shopkeepers ask for it in usability tests or post-pilot feedback, and they already use WhatsApp Business informally, prioritize it in Phase 9 (pilot hardening) or Phase 10+.

### Confidence: **High**

### Implication if Wrong
Shopkeepers who want to share receipts do it manually via WhatsApp (screenshot + message) — current practice. No blocking issue for pilot.

---

## Question 7 — Cost Capture on Bono

### Options

| Option | |
|---|---|
| A | Unit cost only per line |
| B | Line total only per line |
| C | Both, with toggle (one auto-computes from the other) |
| D | C + optional per-line discount field |
| E | C + supplier-level discount + tax fields |

### Evidence

**Bono format in Somalia:**
- A "bono" is the supplier delivery note / informal invoice. Format varies widely by supplier:
  - Some list: Item, Qty, Unit price → Line total
  - Some list: Item, Qty → Line total only (no per-unit price shown)
  - Some list: Item → Total only (no per-item breakdown)
- The `ux.md §5` already shows the per-unit ↔ line-total toggle on the receive screen:
  > "Cost toggle (per-unit ↔ line-total) per line; the other side is auto-computed. Removes 'is this per bag or total?' hesitation."

**Discounts on bonos:**
- Volume discounts: occasionally given by wholesalers for large orders, but typically baked into the unit price rather than shown as a separate line. Separate discount lines are rare on informal Somali bonos.
- Multi-cost lines (e.g., delivery fee as a separate charge): rare in small shop context; most suppliers include delivery in the price.

**Taxes:**
- Somalia has a low formal tax compliance rate. The federal and regional governments levy taxes, but small informal traders (the bono-using demographic) rarely have taxes itemized on their delivery notes.
- VAT is in law but enforcement is limited in informal retail.
- Tax fields would add UI complexity for a feature that virtually no pilot user needs.

### Recommendation

**Confirm the current plan: unit-cost ↔ line-total toggle per line. No discount fields. No tax fields in v1.**

- The toggle is sufficient to handle both bono formats.
- If a supplier offers a discount, the shopkeeper simply enters the already-discounted unit cost (which is how they think about it anyway).
- Optional single shop-level tax rate is already mentioned in `ux.md §3a` as a setup option — leave it as a setup field (nullable, defaulting to null) but do not surface it in the bono entry form for v1. If set, it should auto-apply to sale prices (not purchase costs), not to bono receiving.

**Schema confirmation:**
- `transaction_line.unit_amount` and `transaction_line.line_total` are both present.
- The UI computes one from the other; both are stored.
- No schema change needed.

### Confidence: **High**

### Implication if Wrong
None — the toggle covers both cases. If discounts become a frequent request, a `line_discount` column and optional display can be added in v2 without breaking the schema (it's just a computed adjustment to `line_total`).

---

## Question 8 — Sales Pricing Model

### Options

| Option | |
|---|---|
| A | Fixed price only — item price is immutable at time of sale |
| B | Default from item, editable per line via long-press (current plan) |
| C | Default from item, editable per line via direct tap |
| D | No default — price must be entered on every sale |

### Evidence

**Pricing practice in Somali neighbourhood shops:**
- Most standard items have "posted prices" — a bag of rice, a bottle of oil, a kilo of sugar all have known prices in the shop.
- However, **negotiation does occur** for: regular/loyal customers (slight discount), bulk purchases, end-of-day clearance, slightly damaged goods, or when building a relationship with a new customer.
- This matches East African retail broadly: formal retail (supermarkets) uses fixed prices; informal neighbourhood shops (dukaan) retain some flexibility.
- The UX design in `ux.md §4` already handles this elegantly:
  > "Tap an item = +1 to cart (at default price). Long-press an item = numpad for quantity (and optional per-line price override)."
- This design keeps the normal flow (≤5 seconds for cash sale) clean while enabling power-user price overrides without extra taps for the common case.

**Why not direct tap for price edit?**
- Direct tap = price edit would add a mandatory step for every item in the cart, slowing down the sale.
- Long-press = price edit is invisible to non-power-users and adds zero taps to the normal flow.

### Recommendation

**Confirm the current plan: price defaults from item's `sale_price`; override available via long-press on a cart item.**

This is the correct design. No changes needed.

**Additional clarification for schema/RLS:**
- Cashiers should **not** be able to override prices in v1 (see Q4 above). Price overrides should require Owner role. This can be enforced either in the app layer (long-press action checks role) or via a future `allow_price_override` permission flag on the role.
- For v1: hard-code that long-press price override is Owner-only. If this is wrong (i.e., owners want cashiers to adjust prices), it's a one-line change.

### Confidence: **High**

### Implication if Wrong
If more shops use fixed prices exclusively than expected, the long-press feature is just never used — no harm. If shops need mandatory price override per sale, the long-press is still available. There is no downside to this design.

---

## Question 9 — Costing Policy

### Options

| Option | Complexity | Accuracy |
|---|---|---|
| A | Weighted-average cost (WAC) at receive posting; COGS snapshotted at sale | Low | Sufficient for small retail |
| B | FIFO (first-in-first-out) | High | Better for perishables |
| C | LIFO (last-in-first-out) | High | Rarely used; not appropriate here |
| D | Specific identification | Very high | Requires per-unit tracking |
| E | Fixed/manual cost per item | Low | Poor profit accuracy |

### Evidence

**Architecture invariant (already decided):**
- `architecture.md §8a`: "COGS is snapshotted on each sale line at posting time (`cogs_unit_cost`, `cogs_total`); profit reports use the snapshot, never live `avg_cost`."
- `item.avg_cost` is updated at each Receive posting using weighted average.
- `transaction_line.cogs_unit_cost` is set to the item's `avg_cost` at the moment of sale posting.

**Somali shopkeeper mental model:**
- A shopkeeper thinks: "I bought 50 bags of rice at $18 each last month, then 30 bags at $19 each last week. What's my current cost?"
- Weighted average ($18.375 in this case) is a reasonable answer. They don't track individual bag lots.
- FIFO would require tracking exactly which bags are sold first — operationally complex and invisible to the shopkeeper anyway.
- The relevant question for them is: "Did I make money this month?" — not "What was the exact cost of the specific bag I sold at 2pm on Tuesday?"

**COGS snapshot at sale time:**
- Prevents retroactive profit changes when future receives arrive at different costs.
- Standard practice for retail software (Square POS, QuickBooks Simple Start, Odoo Community).
- Prevents a support nightmare where historical reports change without explanation.

**No backdated recomputation:**
- If a receive is voided/reversed, the avg_cost is recalculated but historical snapshotted COGS on past sales are not touched. This is correct behavior.
- A reconciliation view (already in architecture) can surface the delta.

### Recommendation

**Confirm the current plan in full.**

Weighted-average cost updated at each Receive posting + COGS snapshotted on each sale line at posting time. No backdated recomputation. No FIFO.

**User-facing design note:** The shopkeeper should never see the phrase "avg_cost" in the UI. The item detail screen should show "**Last purchase cost: $18.50**" (from `last_cost`) and "**Estimated cost for profit**: $18.38" (from `avg_cost`, labeled plainly). Or just don't show `avg_cost` at all — show it only in the profit report calculation, silently.

**Schema is already correct.** No changes needed.

### Confidence: **High**

### Implication if Wrong
If the business ever needs FIFO (e.g., pharmacy with expiry tracking), it requires adding a cost lot table and significant posting logic changes. This is a material schema migration but the `stock_movement` ledger already provides the data needed to derive FIFO costs later (since each stock_movement has a `unit_cost`). The path exists; just not in v1.

---

## Question 10 — Data Export & Admin Recovery

### Options

| Option | Scope |
|---|---|
| A | CSV export of items only |
| B | CSV export of items + transactions (no in-app correction) |
| C | CSV export + support-assisted void capability (deferred; would require future audited support session) |
| D | Full in-app correction UI for all users |
| E | Direct Supabase dashboard access for support staff |

### Evidence

**What will go wrong in a pilot:**
- Wrong quantity on a Receive (e.g., entered 100 bags instead of 10)
- Wrong price on a sale (e.g., $100 instead of $10.00)
- Wrong customer assigned to a debt sale (party_id pointing to wrong customer)
- Duplicate transaction entered twice
- Receive posted to wrong supplier

**Current architecture constraints:**
- Posted transactions are immutable (architecture invariant). Corrections via reversing entries.
- The current support session role (`architecture.md §8aa`) is setup-only: "explicitly deny insert/update on `transaction`, `payment`, `payment_allocation`, `inventory_adjustment`, and any posting procedures."
- This means support staff currently **cannot fix transaction errors** — they can only fix setup data (items, suppliers, categories).

**Later decision:** v1 disables support codes and keeps support out-of-band through WhatsApp/email. Transaction correction remains owner-controlled for v1; any future support-assisted correction would require a separate audited support-session design.

**Option E ruled out:** Direct Supabase dashboard access for support staff is dangerous (bypasses RLS), not scalable, and unacceptable from an audit perspective.

**Option D (full in-app correction for all users) risks:**
- Cashiers accidentally voiding transactions.
- Owners voiding old transactions to manipulate reports.
- Complexity of "edit a posted transaction" UX is high.

**Minimum viable path:**
1. **CSV export** — critical for owner to have a paper trail and for support to understand the data.
2. **Owner self-service void** — Owner can reverse a transaction within a time window (e.g., 7 days) via a "Reverse this entry" button on the transaction detail screen. The app creates the reversing entry automatically; owner confirms.
3. **Deferred support-assisted correction** — not in v1 while support codes are disabled. If added later, it must be a separately audited support-session design, not ordinary support access.

**CSV export scope for v1 (minimum):**
- **Items export:** `name`, `unit`, `sale_price`, `last_cost`, `current_stock`, `reorder_threshold`
- **Transactions export:** `occurred_at`, `type`, `party_name`, `total_amount`, `paid_amount`, `balance`, `status`, `payment_method`, `notes`
- **Transaction lines export:** linked to transaction, `item_name`, `quantity`, `unit_price`, `line_total`, `cogs_unit_cost` (for owner education)
- **Payments export:** `occurred_at`, `party_name`, `direction`, `amount`, `method`

**Format:** CSV (universal; opens in Google Sheets, Excel, LibreOffice). Date range filter. Triggered from Settings → Export Data.

### Recommendation

**v1 should include three components:**

1. **CSV Export** (items + transactions + lines + payments, with date range filter). Accessed from Settings. No authentication beyond the existing session. Critical for pilot audit trail and support debugging.

2. **Owner self-service void** (within 7 days of posting): A "Reverse this entry" button on any posted transaction's detail screen, visible only to Owner role. Tapping it shows a confirmation screen summarizing what will be reversed (stock effects, balance effects), requires explicit CONFIRM, then calls `post_transaction()` with a reversing entry. The original is never edited; it is marked `voided` via the `reverses_transaction_id` link. After-7-days voids are deferred for v1 unless a separate owner-approved correction process is designed.

3. **No support-session corrections in v1**: support codes are disabled. Support may guide the owner through allowed in-app correction over WhatsApp/email, but support does not post or void transactions.

**What is NOT in v1:**
- In-app editing of existing transactions (violates the immutability invariant).
- Bulk re-import / data correction via CSV upload (useful later but risky in v1).
- Supabase dashboard access for support staff.

### Confidence: **Medium**

The CSV export and owner void are well-scoped. The exact scope of support correction needs emerges from the pilot — teams may need more (e.g., fixing party assignments on transactions) or less.

### Implication if Wrong
If the correction path is too narrow (owner can't easily fix mistakes), shopkeepers will lose confidence in the app's data integrity and stop using it. This is a pilot-killer. Better to err on the side of making corrections easier — the immutability invariant is preserved because corrections are always reversing entries, never edits.

---

## Appendix: What Still Needs In-Country Validation

These items cannot be resolved from desks and require real-world testing in Somalia:

| Item | Action needed | When |
|---|---|---|
| SMS OTP deliverability to Hormuud/Telesom/Golis | Send 10 test OTPs to real numbers on each network via Twilio and Africa's Talking; record delivery rate and latency | Before Phase 1 is complete |
| Supabase region latency | Ping test from Android device on Hormuud 4G (Mogadishu) and Telesom 4G (Hargeisa) to Frankfurt and Mumbai Supabase URLs | Before provisioning Supabase project |
| Currency preference in shops | Ask 5–10 pilot shopkeepers: "Do you track your stock costs in USD or SOS?" | Phase 1.5 usability testing |
| Receipt / paper trail expectations | Ask during usability testing: "Do your customers expect a written receipt? Do you give one?" | Phase 1.5 usability testing |
| Price negotiation frequency | Observe actual sales during usability testing; count how many sales involve a price override | Phase 1.5 usability testing |
| Bono format variation | Collect 10–15 real bonos from pilot supplier relationships; check: unit-price shown, line total shown, discount lines present, tax lines present | Phase 3 preparation |
| Correction frequency | Track how many "oops, I entered this wrong" events occur in first 30 days of pilot; use to calibrate v2 correction tooling | Phase 9 pilot hardening |

---

*Document generated: 2025-01-XX. Sources: Supabase Auth docs, Supabase Regions docs, Wikipedia (Hormuud Telecom, Telesom, Golis Telecom, Somali Shilling, Telecommunications in Somalia, SEACOM cable system), DataReportal Digital 2024 & 2026 Somalia reports, plan.md, architecture.md, ux.md. Confidence levels reflect verifiability of underlying claims.*
