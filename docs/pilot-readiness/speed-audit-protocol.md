# Speed Audit — Recording Protocol

> The speed contract (`CLAUDE.md` "Speed contract") is Dukan's load-bearing UX commitment. Before every pilot release, we record the four critical flows on a real mid-range Android and confirm the numbers still hold. This document is the standing protocol for those recordings.

---

## 1. The four flows + budgets

| Flow | Budget | Notes |
|---|---|---|
| **Cold start → Home** | ≤ 3.0 s | Device powered, app killed, tap launcher icon → first interactive Home frame. |
| **Sale, 1 item, cash** | ≤ 5.0 s | 3 taps from Home: Sale tile → result → SAVE. |
| **Sale, 5 items, cash** | ≤ 20.0 s | 7 taps: Sale tile → 5 results → SAVE. Total ≤ 4 s per item average. |
| **Receive, 10 lines, manual bono** | ≤ 90.0 s | No bono photo; cashier types qty + total each line; ADD LINE × 10; SAVE. ≤ 9 s per line average. |
| **Any tap → visible response** | ≤ 100 ms | Sampled across the recording. Frame-by-frame check on suspect taps. |

---

## 2. Build

The audit runs on a **profile-mode** build. Profile mode has release-equivalent performance with debug-only instrumentation (the `Timing` markers from `lib/observability/timing.dart`) still active.

```bash
cd app/dukan
flutter build apk --profile \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Install on the test device:

```bash
adb install build/app/outputs/flutter-apk/app-profile.apk
```

**Do not** use the debug APK for timing — debug mode is 5–10× slower than release.
**Do not** use the release APK either — `kReleaseMode` is true and the `Timing` SnackBars are tree-shaken out, so you lose the in-recording readout.

---

## 3. Device setup

Targets a typical pilot-shop phone — mid-range Android, ~$120–$180 retail (e.g., Tecno Spark 8, Redmi 10/12, Samsung A14).

Before recording:

1. **Charge to ≥ 80 %.** Modern Androids throttle CPU/GPU below 30 % battery — that skews the audit by 15–25 %.
2. **Cool the phone.** Aim for surface temp < 35 °C. Sitting in the sun, just finished a long video call → put it down for 15 minutes first.
3. **Disable adaptive battery / data saver / battery optimisation** for Dukan in system settings. These can introduce inconsistent throttling.
4. **Force-stop Dukan** between cold-start recordings (`adb shell am force-stop com.example.dukan` — replace with the production package id).
5. **Close background apps.** Sentry uploads, WhatsApp media sync, Play Store updates — any of these can briefly steal CPU.
6. **Disable system animations to 1× (not 0×).** 0× changes the perceived speed in a way that doesn't represent the cashier's experience.
7. **Note Wi-Fi signal strength / cellular bars** and SSID. Re-recordings need to be on the same network to compare apples-to-apples.

---

## 4. Screen recording settings

Use the **OS-native** screen recorder (Android 11+: pull down quick settings → Screen Record; iOS: Control Center → recording dot). Third-party recorders (AZ Screen Recorder, etc.) vary wildly in overhead.

Configure once per session:

| Setting | Value | Why |
|---|---|---|
| Resolution | **720p** | Sufficient for timing; cuts encoder load ~60 % vs 1080p. |
| Frame rate | **30 fps** | 100 ms budget = 3 frames at 30 fps, readable. 60 fps adds load. |
| Bitrate | OS default | The recorder picks something reasonable. |
| Mic | **Off** | Audio encoding is a separate codec; ~3 % CPU saved. |
| Touch indicators | **On** (Developer Options) | The visible touch dot lets you find tap-frame in playback. |

Per-recording:

- Start the recording **before** the action you're timing. For cold start, start the recording, then tap launcher icon.
- Stop the recording **after** the SnackBar from `Timing.endFlow` is fully readable.
- Save the file with a name matching the schema in § 7.

---

## 5. The two-pass methodology

Recording itself has encoder overhead (5–10 % on a HW-encoded mid-range, more on software). To get both honest numbers AND visual evidence:

### Pass A — Instrumented, unrecorded

1. Launch the profile APK.
2. Watch the device screen.
3. Run each flow. The `Timing` SnackBar shows the elapsed total at the end of each flow.
4. Record the SnackBar numbers in the per-flow table (§ 6). Run each flow **3 times**, throw out the slowest, average the other two.

Pass A is the **official audit number**. No encoder skew.

### Pass B — Instrumented, recorded

1. Start screen recording.
2. Run the same flow once per recording.
3. Stop recording.
4. Save the artifact.

Pass B is the **visual evidence** filed alongside the numbers. The recorded number should be within 10 % of Pass A. If it's not, the encoder is too heavy — switch to an external camera (§ 9.5).

---

## 6. Per-flow target table

Fill in for every audit (one section per release). Use the dated subfolder convention in § 7.

```
Device:        Tecno Spark 8 · Android 12 · 64 GB · 4 GB RAM
Network:       4G LTE, 3 bars, "Hormuud" Hargeisa
Battery:       86%
Surface temp:  32 °C
Build:         <git sha>  ·  profile mode
Date:          <YYYY-MM-DD>  ·  <auditor>

Pass A (instrumented, unrecorded — 3 runs, slowest dropped, mean of 2)

| Flow                              | Budget   | Run 1   | Run 2   | Run 3   | Mean   | Δ vs budget | Pass? |
|-----------------------------------|----------|---------|---------|---------|--------|-------------|-------|
| Cold start → Home                 | 3000 ms  |         |         |         |        |             |       |
| Sale, 1 item, cash                | 5000 ms  |         |         |         |        |             |       |
| Sale, 5 items, cash               | 20000 ms |         |         |         |        |             |       |
| Receive, 10 lines, manual         | 90000 ms |         |         |         |        |             |       |

Pass B (instrumented, recorded — 1 take per flow, filed in this folder)

| Flow                              | Pass-A mean | Recorded | Encoder Δ |
|-----------------------------------|-------------|----------|-----------|
| Cold start → Home                 |             |          |           |
| Sale, 1 item, cash                |             |          |           |
| Sale, 5 items, cash               |             |          |           |
| Receive, 10 lines, manual         |             |          |           |

Tap-response audit (frame-by-frame on recorded artifact)

| Tap                                | Frames to visible | ms @ 30 fps | Pass (≤ 100 ms)? |
|------------------------------------|-------------------|-------------|-------------------|
| Home → Sale tile                   |                   |             |                   |
| Sale → search result               |                   |             |                   |
| Sale → SAVE                        |                   |             |                   |
| Receive → ADD LINE                 |                   |             |                   |
```

A flow fails the audit if **Pass A mean** exceeds the budget. Pass B is documentation, not the gate.

---

## 7. File layout

Every audit lives in a dated subfolder:

```
docs/pilot-readiness/
  speed-audit-protocol.md        ← this file (the standing protocol)
  2026-07-12/
    NOTES.md                     ← the filled-in target table from § 6
    pass-a-summary.txt           ← raw Timing SnackBar readings, one per line
    pass-b-cold-start.mp4
    pass-b-sale-1-item.mp4
    pass-b-sale-5-items.mp4
    pass-b-receive-10-line.mp4
    device-info.txt              ← adb shell getprop output (model + Android version)
  2026-07-30/
    ...
```

Keep at most **the last 3 audits**. Older ones get archived into `docs/pilot-readiness/archive/` so the readiness folder doesn't sprawl.

---

## 8. Markers reference

Where the `Timing` calls fire (see `lib/observability/timing.dart`):

| Flow | startFlow | mark | endFlow |
|---|---|---|---|
| `cold.start` | `main()` top | — | `_TodayCardState.initState` first frame |
| `sale` | Home Sale tile tap | `save.tapped`, `cart.cleared` | After cart clears in `_save` |
| `receive` | Home Receive tile tap | `save.tapped`, `lines.cleared` | After lines clear in `_save` |
| `payment` | Home Payment tile tap | `save.tapped`, `cleared` | After clear in `_save` |
| `expense` | Home Expense tile tap | `save.tapped`, `cleared` | After clear in `_save` |

Console output (visible via `adb logcat | grep timing` while plugged in):

```
[timing] sale START
[timing] sale save.tapped 2841ms
[timing] sale cart.cleared 2856ms
[timing] END sale: 2856ms (no budget)
[timing]   · save.tapped @ 2841ms
[timing]   · cart.cleared @ 2856ms
```

The SnackBar at the end of each flow shows the total. Green if a `budgetMillis` was supplied and met; red if exceeded; default colour if no budget.

To add a budget for a specific flow (e.g. during a regression hunt), edit the `Timing.endFlow(context)` call site to `Timing.endFlow(context, budgetMillis: 5000)`. Don't ship those edits to main — they're scratch.

---

## 9. Common pitfalls

### 9.1 The "first-run-after-install" wins

The first cold start after `adb install` reads from a cold cache (filesystem, dex, etc.). Subsequent runs warm. The audit measures **steady-state** cold start — do 2 warm-up runs before the 3 recorded runs.

### 9.2 Sentry init delays cold start

Sentry's first init takes 100–200 ms. If `SENTRY_DSN` is empty in the profile build, Sentry is skipped entirely and cold start is faster than production. To get an honest number, supply a real DSN in the audit build.

### 9.3 Today card hits the network even with SWR

The SWR cache shows yesterday's numbers immediately, but `getTodaySummary` still runs in the background. On a slow network, the SnackBar fires before the network response — that's correct (the cashier sees Home content). But the cold-start total reflects cached-render time, not full-data-loaded time. If the budget needs to reflect full data, mark a second checkpoint in `_TodayCardState` after the network resolves.

### 9.4 The thermal envelope

After 4–5 consecutive flows, mid-range Androids start throttling. The 6th measurement is often 15 % slower than the 1st on the same flow. Cool the phone between segments: do all 3 runs of Sale 1-item, put the phone down for 10 minutes, then do Sale 5-items.

### 9.5 External camera fallback

If Pass B is consistently 15 %+ slower than Pass A, the on-device encoder is too heavy. Use a second device pointed at the test device's screen — that's zero overhead on the device under test. iPhone slow-motion (240 fps) gives precise tap-to-response measurements but produces big files; use it sparingly for the tap-response audit only.

### 9.6 The OS launcher animation

Some Android launchers (One UI, MIUI) add 200–400 ms of animation on the launcher → app transition. That's part of the cold-start experience but not under our control. Document the launcher in `device-info.txt`.

---

## 10. When the audit fails

A failure means a flow's Pass-A mean exceeds the budget. The recovery sequence:

1. **Re-run the failing flow** 5 more times to rule out transient (Wi-Fi spike, Sentry upload).
2. **Compare per-mark deltas** — the `pass-a-summary.txt` lines show which segment of the flow ate the budget. Common culprits:
   - `save.tapped` → `cart.cleared` gap > 50 ms: a stray `await` snuck back in. Check the latest commits touching the relevant `_save` handler.
   - Sale entry → `search.loaded` (would need a new marker) > 500 ms: favorites cache cold (Today card prefetch failed); inspect Sentry for errors.
   - Cold start total but no mark gap obvious: rebuild deps, check Sentry/Supabase init latency.
3. **File the failure** in the dated subfolder's NOTES.md with the run logs.
4. **Open a regression-hunt task** in the planning tracker; do not pilot-release until it's resolved.

---

## 11. Companion documents

- `CLAUDE.md` § "Speed contract" — the binding numerical commitments.
- `docs/ux.md` — the interaction rules these numbers protect.
- `docs/mobile-app-alignment.md` § 3.5 — the alignment item this protocol closes.
- `lib/observability/timing.dart` — the instrumentation this protocol relies on.

---

## 12. Change log

| Date | Change | Author |
|---|---|---|
| 2026-06-11 | Initial protocol drafted. | — |
