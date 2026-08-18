---
name: breezymac-phase-and-open-questions
description: BreezyMac current phase, mode model, and the detailed next-step (popover) spec
metadata:
  type: project
---

BreezyMac (macOS fan-control app, `org.WhoCo.BreezyMac`) — on branch `main`,
builds clean via `make build`, tested on-device (macOS 26). `CLAUDE.md` is the
authoritative architecture/safety doc; [[breezymac-user-preferences]] and
[[breezymac-reference-projects]] hold user tastes and reference lessons.

## Current mode model (Silent removed)

`Disabled / Automatic / Adaptive / Performance`, all **power-source aware**
(AC vs battery via IOKit `PowerSourceMonitor`):
- **Disabled** — return control to macOS (safe default; daemon not registered
  until an engaging mode first needs it; need not unregister on Disabled).
- **Automatic** (flagship anti-throttle) — proportional ramp between per-source
  target/ceiling temps + dT/dt anticipation term + max override when
  `ProcessInfo.thermalState` ≥ `.serious` OR temp ≥ ceiling; rise-fast/decay-slow.
- **Adaptive** — user curves, now **power-source aware** (separate AC/battery
  sets) with a selectable interpolation mode (linear vs monotone-cubic "smooth").
- **Performance** — all fans max.

## On-device validation / tuning outcome

- Automatic works well; **temperature setpoints do essentially all the work** —
  `thermalState` stayed `.nominal` throughout on this M-series even under load,
  so the thermalState override is a rarely-hit safety net (keep it).
- Anticipation slider is a hit; **default set to 0.15** (was 0.5). User likes
  ~12% personally. Default change affects **new installs only** (persisted
  configs keep their value).
- Added a **guard so Automatic target stays ≥5 °C below ceiling** (setting
  ceiling<target caused fan oscillation).
- Power-source switch verified live (unplug → battery config, replug → AC).
- **Hot-spot sensor fix (commit 8ea46ce):** temps previously read ONE sensor
  (first plausible key in a fallback list, e.g. `Tp09`) → missed the throttle
  hot spot (a GPU-bound load throttled while our reading stayed "in range").
  Now `SMCReader` enumerates the SMC once (`#KEY` + read-by-index) and reads the
  **MAX** across the Apple-Silicon die sensors — `Tp`/`Te` (CPU cores), `Tg`
  (GPU) — every tick; Intel/none falls back to the curated lists. Logs resolved
  keys once via NSLog for on-device verification. **Pending user re-test.** If a
  group resolves to odd/empty keys, refine the prefix filter.

## Build order & status

Steps 1–3 DONE (foundations, mode-model change, Automatic controller + settings
tab). **Step 4 (popover + Swift Charts) IMPLEMENTED & building clean** (commit
ba0546e "Step 4a"): NSMenu→NSPopover hosting a mode switcher + toggleable text
indicators + two stacked synced charts; new `PopoverSettings` model + "Popover"
config tab; Fans/Sensors tabs removed; Automatic "Reset to Defaults" button
added; `TelemetrySample` gained `batteryTemp`. **Popover VERIFIED on-device**
(commits 4b/4c fixed: off-screen/gap positioning via `.fixedSize` + hosting
`sizingOptions`; hide chart when its series toggled off; pinned x-axis labels).

**Step 5 (Adaptive power-source curves + linear/monotone-cubic) IMPLEMENTED &
building clean** (commit f981a46): `FanCurveConfig` → `interpolation` +
`ac`/`battery` curve sets; `targetFraction(for:source:)`; new
`CurveInterpolation {linear, smooth}` where smooth = monotone-cubic
(Fritsch–Carlson), default smooth; Curve tab rewritten with a Smoothing picker,
an AC/Battery selector, and a live preview chart + Reset. **Refined after test:**
user prefers smooth → **linear dropped entirely** (curves always monotone-cubic;
Smoothing picker + dashed overlay removed); **GPU curve now enabled by default**
per source so GPU-bound loads are protected.

**Step 6 (config-window restructure) IMPLEMENTED & building clean** (commit
c14d22a): top TabView → macOS Settings-style **NavigationSplitView sidebar**
(General / Automatic / Adaptive / Popover / Helper / About). General now = mode
+ at-a-glance status (power/thermal/helper); **Helper install + startup split
out** of the old General into its own page; Curve page relabeled "Adaptive";
mode-specific pages editable regardless of active mode; window 700×480 (min
660×470). Step-6 direction was under-specified — chose a Settings-sidebar;
**open to redirection after on-device look.** Still open: CPU/GPU-utilization
inputs to the algorithms; the deferred visual/aesthetic pass (translucent cards,
animations).

### Step 4 implementation choices (may revisit after on-device test)
- Refresh interval = **display subsampling of the fixed 2 s control tick**
  (range 2–10 s), NOT a second timer — heartbeat/watchdog cadence untouched
  (invariants #1/#5). Control temps stay fresh between display frames.
- Lower chart draws **one line per fan**. Palette = **Okabe–Ito** (CVD-safe):
  CPU vermillion / GPU blue / Battery green; fans sky-blue/mauve/orange. Color
  keyed to series identity (never cycled), via `chartForegroundStyleScale`.
- Fixed **5-min** rolling window; only the lower chart shows x-axis labels
  ("now"/"Nm") so the shared time axis reads as one. History accrues only on
  display frames while the popover/window is visible (background sampling still
  the deferred toggle).

### Step 4 spec (FINALIZED — all refinements confirmed) — status-bar NSPopover + Swift Charts
- Replace today's status-bar **NSMenu** with a SwiftUI **NSPopover** (chillmac-
  style): mode switcher + live charts + Open Configuration + Quit. Refresh ~2 s
  (interval configurable in the Popover tab).
- **Charts: TWO STACKED charts sharing one synchronized time x-axis** — temps
  (°C) on top, fan speed (RPM) below. NOT a single dual-y-axis chart (different
  scales read as busy/misleading). Uses native `Charts` (Swift Charts), no dep.
- Temp lines: CPU / GPU / Battery, each toggleable. **Defaults: CPU + GPU ON,
  Battery OFF.** Fan speed shown per fan (or aggregate) on the lower chart.
- **Text indicators**: a compact header row above the charts (current CPU/GPU
  temp, fan RPM), each toggleable, sensible ones ON by default.
- **Fixed rolling window** (~3–5 min, capped points) so render cost is trivial.
- Persist the show/hide toggles + refresh interval via a new **`PopoverSettings`
  model in AppState** (UserDefaults-backed).
- Add a **"Popover" config tab** with the line/indicator checkboxes + refresh
  interval + (later) a background-sampling toggle.
- **Remove the Fans and Sensors tabs** from the config window (intent moves to
  the popover).
- Data source: `AppState.history` rolling buffer already exists (accrues while
  UI visible). Low-frequency **background sampling** to keep history warm when
  closed is a **separate later task** (toggle in the Popover tab).
- Nice-to-have: a **"Reset to defaults" button** for Automatic (its default
  anticipation changed to 0.15, and there's currently no way back without
  clearing prefs).

## Deferred / later
Step 5 Adaptive AC+Battery curves & monotone-cubic; step 6 config restructure;
CPU/GPU-utilization inputs to Automatic; unit tests for pure logic (FanCurve,
SMCDecode, AutomaticController); Silent 0-RPM exploration; release
signing/notarization; Swift 6 language mode.
