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
- **Adaptive** — user curves (AC + Battery split still TODO, see step 5).
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

## Build order & status

Steps 1–3 DONE (foundations, mode-model change, Automatic controller + settings
tab). **NEXT = step 4 (popover + Swift Charts).** Then 5 (Adaptive AC/Battery
curves + monotone-cubic-vs-linear), 6 (config-window restructure).

### Step 4 spec (agreed) — status-bar NSPopover with Swift Charts
- Replace today's status-bar **NSMenu** with a SwiftUI **NSPopover** (chillmac-
  style): mode switcher + **live Swift Charts** (native `Charts`, no dependency)
  + Open Configuration + Quit. Refresh ~2 s (make interval configurable).
- Charts: temperature history with **CPU / GPU / Battery** lines, and **fan
  speed on the same timeline**. Allow **per-line show/hide** (e.g. hide battery
  temp). Optional **text indicators** (current fan RPM, CPU/GPU temps) that users
  can toggle on/off.
- Add a **"Popover" config tab** with checkboxes controlling which plot lines +
  text indicators appear.
- **Remove the Fans and Sensors tabs** from the config window (their intent
  moves into the popover).
- Data: `AppState.history` rolling buffer already exists (accrues while UI
  visible). Optional low-frequency **background sampling** to keep history warm
  when closed is a **separate later task** (make it a toggle in the Popover tab).

## Deferred / later
Step 5 Adaptive AC+Battery curves & monotone-cubic; step 6 config restructure;
CPU/GPU-utilization inputs to Automatic; unit tests for pure logic (FanCurve,
SMCDecode, AutomaticController); Silent 0-RPM exploration; release
signing/notarization; Swift 6 language mode.
