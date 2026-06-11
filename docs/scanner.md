# Scanner Integration — Design

> **Target state**, not as-built. This doc is the design contract for **how barcodes enter the Dukan mobile app**: which input modalities we support, where scanning surfaces, how unknown codes are handled, how it's gated by capability, and how it stays out of the way when not needed.
>
> Scope is **deliberately wider than "wire up `mobile_scanner`"**: there are at least four realistic ways a barcode arrives at the cashier's hand (phone camera, Bluetooth HID scanner, USB-OTG scanner, photo decode), and the v1 choices we make have multi-year consequences for which hardware our pilot shops can use without rework.
>
> Companion documents:
> - `docs/mobile-app.md` § 6.1 + § 7.3 — Sale, Receive, and Product detail surfaces where scanning lives.
> - `docs/mobile-app-alignment.md` § 3.2 — the alignment punch list item this doc unblocks.
> - `docs/backend-schema.md` — `shop_item_barcode` (per-packaging) and `search_items` (already barcode-aware).
> - `docs/roles-and-permissions.md` — capability vocabulary for the cashier-search vs. owner-bind distinction.
> - `docs/ux.md` — the binding speed contract; scanning has to honour it.

---

## 1. Purpose

A barcode is the **fastest possible input** for a cashier already holding the product. The current Dukan app supports barcodes in three places — `shop_item_barcode` exists per packaging (`shop_item_unit_id`), `search_items` matches barcodes typed into the search field, and Product detail's per-packaging barcode chips let an owner bind/promote/remove codes — but the cashier-facing experience is still "type the digits into the search bar." That's the inverse of the speed contract.

This doc commits to: **camera scan ships in v1; HID-keyboard scanner detection ships in v1; both work in Sale, Receive, and Product detail with consistent UX; cashier-and-owner capability split is honoured; multi-scan mode for Receive is a primary feature; the design accommodates BT SPP/BLE and NFC in v2 without rework.**

## 2. Target state in one paragraph

In v1, the cashier sees a small camera icon at the right edge of the search bar on Sale and Receive. Tapping it opens a viewfinder; the first successful decode adds the item to the cart (Sale) or stages the next line (Receive) with a soft beep + haptic, and closes the sheet. A long-press on the same icon (or toggling the Receive screen's "Multi-scan" chip) flips to multi-scan mode — successful decodes auto-stage and the viewfinder stays open until dismissed. Cheap Bluetooth HID scanners (the dominant shop-floor hardware) work everywhere a search bar is focused — the keystrokes are auto-detected as a scan when they arrive in a sub-50ms burst terminated by Enter. Unknown codes show an inline "Unknown barcode — bind to a product?" pill: cashier sees "ask the owner" wording; owner sees the bind flow. Product detail has a per-packaging "+ Add code via scan" entry next to the existing "+ Add manually" chip.

## 3. Modalities — the input matrix

There are four realistic ways a barcode enters the app today. We commit to two in v1, design-for two in v2, and explicitly reject one.

### 3.1 Phone camera (v1)

The phone's rear camera, viewfinder open, decode on-device. Standard for one-off use; slow for high-volume scanning because of focus + decode latency (typically 300–800ms per scan).

- **When it's the right tool:** ad-hoc Sale lookup, Product detail bind, Settings scanner test, low-volume Receive.
- **When it's not:** a Receive flow with 20 lines. The viewfinder dance kills the speed contract.
- **Tech:** `mobile_scanner` package (Flutter-native, ML Kit on Android, Vision on iOS). Supports the v1 symbology set.
- **Permission:** camera permission requested on first tap with a bilingual rationale.

### 3.2 Bluetooth HID scanner (v1)

A cheap (~$20–50) standalone scanner pairs as a Bluetooth keyboard. When the scanner trigger fires, the device emits the decoded code as a burst of keystrokes followed by Enter (Carriage Return). The phone OS sees it as keyboard input and routes it to whatever text field is focused.

- **Why it dominates real shops:** sub-second scan-to-result, dedicated trigger button, no camera/screen lock issues, $20 entry point.
- **The detection trick:** keystrokes arriving < 50ms apart for ≥ 4 chars terminated by `\n` is a scan; slower keyboard typing is a human. Heuristic, but reliable in practice.
- **Tech:** `RawKeyboardListener` / `HardwareKeyboard.instance.addHandler` wraps the OS keyboard stream; the heuristic above flags scan bursts.
- **No app permission needed** — Bluetooth pairing is system-level.

### 3.3 USB-OTG scanner (v1, free)

Android allows wiring a USB scanner via an OTG cable; the scanner enumerates as a HID keyboard. Behavioural twin of § 3.2 — same detection heuristic, no extra code path.

- **Listed separately** so future readers know it's covered, not because it's a separate engineering item.

### 3.4 Scan-from-photo (v2 design-for, not v1)

User picks a photo from gallery; ML Kit decodes barcodes in it.

- **Why deferred:** the use case is narrow ("I took a photo of the box yesterday and want to look it up now") and the bono OCR path already covers most "retrospective decode" needs.
- **Why design-for:** when we add it, it shares the decode pipeline with § 3.1 — same symbology, same handler. No architectural blocker.

### 3.5 Bluetooth SPP / BLE direct (v2 design-for, not v1)

Some scanners offer a serial/BLE profile that an app subscribes to directly. Faster than HID in theory; in practice the integration is finicky and the BT HID profile (§ 3.2) covers > 95% of shop-floor scanners.

- **Why deferred:** maintenance cost vs. user value. v1 ships HID; if a pilot shop hits a scanner that *only* speaks SPP, we add a per-vendor profile then.

### 3.6 NFC tags (v2 design-for, not v1)

Adjacent technology in the "scan-to-identify" bucket. Some wholesalers use NFC tags on pallets.

- **Why deferred:** not in pilot scope. Add when a real pilot shop asks.

### 3.7 Explicitly rejected: built-in barcode picker

iOS / Android both ship a native barcode picker UI; we **do not use it**. Reasons:

- Visual inconsistency between platforms.
- No multi-scan mode.
- No torch control from app.
- Can't bypass the picker chrome.

The `mobile_scanner` viewfinder is consistent across platforms and gives us control.

---

## 4. Where scanning lives

Four entry points. Each surfaces consistently — same camera-icon affordance, same gestures, same feedback. Behaviour after a successful decode differs per surface.

### 4.1 Sale screen

- **Affordance:** camera icon at the right edge of the search bar, inside the field decoration.
- **Tap:** opens single-scan viewfinder. First decode → look up via `search_items` → if matched, add to cart with same code path as a search tap; viewfinder closes.
- **Long-press:** opens multi-scan viewfinder (see § 5.3).
- **HID burst arrives while Sale screen is focused:** treated as if the cashier had typed the code + Enter; if matched, add to cart.
- **Unknown code:** see § 7.

### 4.2 Receive screen

- **Affordance:** identical to Sale — camera icon in the search bar.
- **Tap:** opens single-scan viewfinder. First decode → look up → if matched, stage the line and re-open the search bar focused (so the cashier can scan the next line by tapping again, or by tapping the icon, or just by pressing the HID trigger).
- **Long-press / "Multi-scan" chip:** opens multi-scan viewfinder. Successful decodes auto-stage lines without closing the viewfinder. A counter chip top-right shows "N lines staged so far." Tap × or back to exit.
- **HID burst:** same as Sale.
- **Unknown code:** see § 7.

### 4.3 Product detail (owner-only)

- **Affordance:** on each packaging tile, a small "+ Add code via scan" action next to the existing "+ Add manually."
- **Tap:** single-scan viewfinder. On decode → call `add_shop_item_barcode` with `is_primary=false` (cashiers can promote later via the existing chip-action menu). Toast confirms binding.
- **No multi-scan mode** here — binding many codes is rare; the loop is dominated by the picker, not the scan.

### 4.4 Settings → Tools → Test scanner

- **Affordance:** a list entry in Settings → Tools (a new sub-section).
- **Tap:** opens a screen with a single button "Open viewfinder" and a live readout of (a) current detected scanner mode (Camera / HID-keyboard-detected / None), (b) last decoded value, (c) symbology, (d) timestamp.
- **Purpose:** support staff diagnose hardware before training a shopkeeper. Owner-only, gated behind a `settings.tools` capability so cashiers don't accidentally land here.

### 4.5 Not an entry point: bono OCR

The bono image OCR pipeline (Receive screen → "Take photo of bono") is structurally separate. It decodes text + table layout, not codes. Future work may bridge the two (a bono with a printed line-item barcode could feed the same search index) but that's v2 territory and lives in `docs/architecture.md` § OCR, not here.

---

## 5. Trigger model

### 5.1 Camera: tap to open

Default behaviour. The camera viewfinder is **not** ambient — it opens on explicit tap to (a) preserve battery, (b) keep the camera available to other Flutter widgets (e.g., bono photo), (c) avoid the "scanning chime" surprising a cashier who isn't ready.

### 5.2 HID: always-on listen

When **any** search-bar `TextField` is focused, the HID listener is armed. A burst arriving while no search bar is focused is **dropped silently** (we don't want a scan to land in an unrelated text field — like a customer-name input).

Exception: on Sale and Receive home screens, the HID listener arms the same heuristic on screen-focus, not text-focus — the cashier's hand might be on the trigger before the search bar is tapped. The first scan implicitly focuses the search bar.

### 5.3 Multi-scan mode (Receive only, v1)

Long-press on the camera icon or tap the explicit "Multi-scan" chip. The viewfinder opens and stays open. Successful decodes auto-stage a line; the cashier sees a brief "+1" toast at the bottom of the viewfinder; the counter chip ticks up. Exit via × or back button.

In multi-scan mode:

- **Unknown codes** are queued (not staged) and shown as a "skipped: 3" indicator. After exit, the screen surfaces the queue with the standard "bind / create / dismiss" UI.
- **Default packaging assumption:** every staged line uses the matched packaging's defaults — quantity 1 in the scanned packaging's unit, default cost-entry mode. If the cashier needs to override quantity (rare for Receive multi-scan), they do it after exit by tapping the staged line.
- **Same-code-twice:** scans of the same code increment the existing line's quantity, just like a tap on a duplicate search result does today.

### 5.4 Single-scan mode (default)

Decode → act → close. The "act" depends on the surface — see § 4.

---

## 6. Symbology support

| Symbology | v1 default | v1 opt-in | v2 |
|---|---|---|---|
| EAN-13 | ✅ | — | — |
| EAN-8 | ✅ | — | — |
| UPC-A | ✅ | — | — |
| UPC-E | ✅ | — | — |
| Code128 | ✅ | — | — |
| Code39 | — | ✅ Settings toggle | — |
| ITF-14 (case label) | — | ✅ Settings toggle (Receive only) | — |
| QR | — | — | ✅ |
| Data Matrix | — | — | ✅ |
| PDF417 | — | — | ❌ (not relevant for retail) |

EAN-13 + EAN-8 + UPC-A/E cover essentially all packaged retail goods. Code128 covers shop-printed labels. The opt-in toggles exist for the rare shops that need them; default-off avoids false positives.

The toggle lives at Settings → Tools → Scanner symbologies. Owner-only.

---

## 7. Unknown-barcode handling

After every decode, the app calls `search_items(shop_id, scanned_code, screen)`. Three outcomes:

### 7.1 Exactly one match

Drop into the surface's normal happy path: Sale adds to cart, Receive stages a line, Product detail binds. No additional UI.

### 7.2 Zero matches

Show an inline pill at the top of the screen:

> Unknown barcode `1234567890123` — bind to a product?
>
> [Bind to existing]    [Create new]    [Dismiss]

Capability-gated:

- **Cashier:** the pill reads "Unknown barcode — ask the owner." Bind / Create are hidden; only Dismiss is available.
- **Owner:** all three actions available. "Bind to existing" → product picker → on pick, calls `add_shop_item_barcode` then performs the surface's happy-path action. "Create new" → existing add-new-item sheet pre-filled with the scanned code as the primary barcode.

In multi-scan mode, the pill is replaced by a "Unknown: N" counter; the queue is reviewed after exit.

### 7.3 Multiple matches

Shouldn't happen — `shop_item_barcode` is unique per `(shop_id, code)`. If it does (data corruption, legacy import), the app shows a disambiguation list with the matching products and the cashier picks one. The owner is shown an additional "Fix duplicate" action that opens an audit-log inspection of the colliding rows.

### 7.4 Global catalog match (no shop binding yet)

Some scans match `item_barcode` (global catalog) but no `shop_item_barcode` (this shop hasn't activated the item). Already handled by `search_items` per migration 0045 — the result row carries an "activate?" flag. Pill surfaces "This product is in the catalog — activate for your shop?" with the owner-only Activate action.

---

## 8. Capability gating

Maps to `docs/roles-and-permissions.md` capabilities:

| Action | Capability | Cashier | Owner |
|---|---|---|---|
| Open camera scanner from Sale / Receive | `sale.search` / `receive.search` | ✅ | ✅ |
| Open camera scanner from Product detail | `inventory.product.edit` | ❌ | ✅ |
| Bind unknown code to existing product | `inventory.barcode.bind` | ❌ | ✅ |
| Create new product from unknown code | `inventory.product.create` | ❌ | ✅ |
| Activate a globally-known code into the shop | `inventory.product.activate` | ❌ | ✅ |
| Promote a code to primary | `inventory.barcode.primary` | ❌ | ✅ |
| Remove a code | `inventory.barcode.remove` | ❌ | ✅ |
| Toggle symbology in Settings | `settings.tools` | ❌ | ✅ |
| Open scanner test screen | `settings.tools` | ❌ | ✅ |

Gating depends on the capability refactor (`mobile-app-alignment.md` § 2.1, task #229). Until that lands, the scanner ships with the hardcoded `auth_can_post_shop` / owner-role checks the rest of the app uses; the action surface is the same.

---

## 9. Feedback and viewfinder UX

### 9.1 Audio

- **Successful decode:** soft "beep" (~80ms, 800Hz). Default on; configurable in Settings → Tools → Scanner feedback. Mutes when the system silent switch is engaged (iOS) or Do-Not-Disturb is on (Android).
- **Unknown decode:** silent. The pill is the feedback; an error beep on every unmatched code is unpleasant.
- **Multi-scan duplicate (same code rescanned):** softer "tick" half the beep volume so the cashier knows "yes I heard you, line +1."

### 9.2 Haptic

- **Successful decode:** medium-impact haptic (`HapticFeedback.mediumImpact`).
- **Unknown decode:** light selection click only when in multi-scan mode (so the cashier knows something happened without looking).
- **Failure to acquire focus (camera busy):** error vibration.

### 9.3 Visual

Viewfinder layout:

```
┌─────────────────────────────────────┐
│  ←       Scan a barcode        ⚡   │
│                                     │
│                                     │
│       ╔═══════════════════╗         │
│       ║                   ║         │
│       ║                   ║         │
│       ║       (camera)    ║         │
│       ║                   ║         │
│       ║                   ║         │
│       ╚═══════════════════╝         │
│                                     │
│         Multi-scan: 7              │
│                                     │
└─────────────────────────────────────┘
```

- Back arrow top-left.
- Title bilingual ("Scan a barcode" / "Akhri jeeg").
- Torch toggle ⚡ top-right.
- Reticle (the dashed rectangle) in the middle ~70% width.
- On success: reticle briefly flashes green (~250ms) before close (single-scan) or clear (multi-scan).
- On unknown: reticle briefly flashes amber.
- Multi-scan counter visible at bottom; absent in single-scan.

### 9.4 Torch

Off by default. Toggle persists for the session (not across launches — a low-light shop sets it once per evening). Long-press the torch icon turns it on permanently for that shop (persisted per device in Settings). Owner can flip the per-shop default in Settings.

### 9.5 Reticle hint

If no decode for > 3 seconds, show a small hint: "Hold steady — 15–25cm from the code" in both languages. Disappears as soon as anything is decoded (even a non-matching code).

---

## 10. Permissions

### 10.1 Camera

Requested on the first camera-icon tap, not at app launch. Rationale dialog:

> **Dukan wants camera access**
>
> Dukan uses the camera to scan product barcodes. Photos of the barcode never leave your phone.
>
> [Allow] [Don't allow]

(Bilingual; Somali variant identical in structure.)

If denied:

- The camera icon is greyed out with a small lock icon overlay.
- Tapping shows: "Camera blocked. Open phone Settings → Apps → Dukan → Permissions to enable scanning."
- Deep-link to system settings via `permission_handler.openAppSettings()`.

If denied permanently (Android: "Don't ask again"; iOS: never re-prompted): same UX — the deep-link is the recovery path.

### 10.2 Bluetooth

No app permission needed for HID scanners — pairing is OS-level and the scanner appears as a keyboard.

### 10.3 No scanned-frame persistence

Decode happens on each frame in-memory; we never write the camera frame to disk or send it anywhere. The decoded *string* is the only persisted/transmitted artefact.

---

## 11. Offline behaviour

- **Camera decode** runs locally. Works offline.
- **Lookup (`search_items`)** hits Supabase. If offline:
  - Cashier sees a yellow banner: "Working offline. Scanned codes will resolve when you reconnect."
  - Scanned-code → cached local index of `shop_item_barcode` (seeded from the last successful `list_shop_items` for this shop). If cached, line added.
  - If not cached, the scan is staged as an "unresolved line" with the raw code as the placeholder name; the offline write queue (`mobile-app-alignment.md` § 3.9, task #232) resolves it at sync time.
- **Bind unknown** offline: the bind request joins the write queue with `client_op_id` idempotency. Multiple offline binds of the same code resolve to one server-side bind.

Until the write queue ships, offline scanning shows the inline banner and queues *reads* in memory only; offline binds are blocked with a "Connect to bind a code" message.

---

## 12. Tech stack

### 12.1 Camera

- Package: `mobile_scanner: ^5.x` (latest stable at integration time).
- Symbology config: `MobileScannerController(formats: [...])` initialised from the v1 default set + opt-in additions from Settings.
- Decode rate: device default (mobile_scanner handles throttling).
- Frame skip in low-end devices: rely on package defaults; if performance becomes an issue, set `detectionTimeoutMs` to 250ms.

### 12.2 HID listener

- `lib/scanner/hid_listener.dart` — new file.
- Wraps `HardwareKeyboard.instance.addHandler` (Flutter 3.x) at app start.
- Maintains a sliding buffer of the last 16 keystrokes + timestamps.
- Heuristic: when an Enter arrives, look back: if the previous ≥ 4 keys arrived in a window < 200ms total *and* are all printable characters, emit a `ScanEvent(code, source: hid)`.
- Subscribed to by Sale, Receive, Product detail, and the test screen via a `ChangeNotifier`-style stream.
- **Drops events** when no eligible screen subscribes — keeps background screens from absorbing a stray scan.

### 12.3 Shared scanner controller

- `lib/scanner/scan_controller.dart` — single source of truth for "did a scan happen, and what was the code."
- Emits `ScanEvent { code, symbology, source: camera|hid, at }`.
- Camera and HID feed into it; the rest of the app reads from it.
- Plays the beep + haptic at the controller layer so every surface gets consistent feedback.

### 12.4 No native channels written from scratch

Both camera and HID use existing packages and Flutter APIs. No platform-channel maintenance burden in v1. (BT SPP in v2 would need one; we accept that when we get there.)

---

## 13. Telemetry

For the speed audit (`mobile-app-alignment.md` § 3.5) and ongoing health:

- Tag every `ScanEvent` with `source` (camera vs HID), `symbology`, `match outcome` (matched / unknown / global-catalog / multi-match), `latency` (decode → result rendered).
- Aggregate per session: scan count, scan latency p50/p95, unknown-rate.
- Surface in Sentry as breadcrumbs (not events) so a crash report shows what the cashier was doing.
- Per-shop telemetry exported nightly to the platform admin's observability stack — *no scanned code values* in the export, only the metadata above.

## 14. Privacy

- **No scanned-code values leave the device** except via the `search_items` / `add_shop_item_barcode` RPC calls, which already log them in `audit_log` for binds.
- **Sentry breadcrumbs** never include the code string — only metadata (`source: camera, outcome: matched, latency: 420ms`).
- **No camera frame persistence** (§ 10.3).
- **No third-party SDK with internet access** introduced — `mobile_scanner` is on-device.

---

## 15. What this doc deliberately does NOT cover

Permanent boundaries / deferred until v2:

1. **BT SPP / BLE direct.** § 3.5 — HID covers > 95%.
2. **NFC tags.** § 3.6 — not in pilot scope.
3. **Scan-from-photo.** § 3.4 — bono OCR covers retrospective decode.
4. **2D codes (QR / Data Matrix).** § 6 — not common on retail goods.
5. **In-app Bluetooth pairing UI.** OS-level pairing is more reliable than re-implementing it.
6. **Scale-integrated scanners (weighing scale that prints a code).** Specialty hardware; not pilot scope.
7. **Loyalty-card scan in Sale.** No loyalty engine in v1.
8. **Receipt-barcode scan for void.** Voids already happen via Sales history search; barcode-of-receipt would be sugar.
9. **Auto-bind on first unknown scan.** Always require confirmation — silent auto-bind risks the cashier mis-binding a wholesale code to the wrong SKU.
10. **Cashier-initiated bind.** Binding is owner-only (catalog mutation). Cashier sees "ask the owner" pill.

---

## 16. Implementation phasing

The implementation task (#227) breaks into three PRs so each can ship and validate independently:

### Phase 1 — foundation
- Add `mobile_scanner` dependency.
- Add `lib/scanner/scan_controller.dart` + `lib/scanner/hid_listener.dart`.
- Add `lib/scanner/scanner_sheet.dart` (single-scan viewfinder UI).
- Wire camera icon into Sale search bar only. Single-scan only. No multi-scan, no HID, no Receive, no Product detail.
- Wire unknown-code pill for the owner role.
- Backend: no migration needed (all RPCs exist).

### Phase 2 — Receive + multi-scan
- Wire camera icon into Receive search bar.
- Implement multi-scan mode.
- Implement HID listener arming on Sale + Receive.
- Wire the "Unknown: N" queue + review-on-exit flow.

### Phase 3 — bind everywhere + diagnostics
- Wire Product detail "+ Add code via scan" per packaging.
- Wire Settings → Tools → Test scanner screen.
- Wire symbology Settings toggle.
- Tighten audio/haptic per § 9.

Each phase is a separate PR; alignment doc § 3.2 can be ticked off after Phase 3.

---

## 17. Open questions for the user

These are the calls that need explicit confirmation before implementation starts. The defaults below are the answers I'd ship with if no objection.

| Question | Default |
|---|---|
| Camera icon position — inside the search field decoration, or as a separate trailing FAB? | Inside the field. Consistent with the existing search-icon affordance. |
| Multi-scan affordance — long-press the icon, or a separate chip on the screen? | **Both.** Long-press is the power-user shortcut; the chip is discoverable for new cashiers. |
| Audio/haptic default on or off? | **On.** Cashiers expect a confirmation; can be muted in Settings. |
| Symbology defaults — should ITF-14 (case label) be on for Receive screen only, or off everywhere by default? | **Off everywhere by default**; per-screen toggle adds UI complexity for a feature most pilot shops won't need. Toggle on, scope unified. |
| Unknown-code-pill placement — top of screen, or floating bottom-sheet? | **Top inline pill.** Pulls less focus than a sheet; doesn't obscure cart. |
| Should we play the *unknown* beep at all? | **No.** Visual pill is enough; audio for unknowns is annoying in busy shops. |
| Bono image barcode decode — same pipeline, or separate? | **Separate for v1.** Bono OCR is already its own thing; revisit after Phase 3 ships. |

---

## 18. Speed contract impact

The scanner exists to *advance* the speed contract, not regress it. Targets, measurable in the recorded audit (`mobile-app-alignment.md` § 3.5):

- **Camera tap to viewfinder visible:** ≤ 200ms.
- **Viewfinder open to first decode (good light, clear code):** ≤ 600ms.
- **Decode to cart line (Sale, matched):** ≤ 300ms.
- **HID scan-burst to cart line:** ≤ 250ms (HID is faster than camera; budget reflects it).
- **Multi-scan Receive — 10 lines:** ≤ 30s end-to-end. Compares against the current "≤ 90s, manual 10-line bono" budget.

If any of these regress on the recorded audit, the relevant phase blocks until it's fixed.

---

## 19. Companion documents

- `docs/mobile-app.md` § 6.1, § 6.2, § 7.3 — the screens this integrates with.
- `docs/mobile-app-alignment.md` § 3.2 — the alignment item this unblocks.
- `docs/backend-schema.md` — `shop_item_barcode`, `search_items`, `add_shop_item_barcode`, `set_primary_shop_item_barcode`, `remove_shop_item_barcode` (all already present).
- `docs/roles-and-permissions.md` § 6 — capability vocabulary for the gating table in § 8.
- `docs/ux.md` — speed contract these targets honour.
- `docs/architecture.md` § OCR — adjacent pipeline (bono image decode); intentionally separate.

---

## 20. Change log

| Date | Change | Author |
|---|---|---|
| 2026-06-11 | Initial draft. | — |
