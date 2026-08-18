---
name: breezymac-phase-and-open-questions
description: BreezyMac current project phase, resolved design decisions, and what's next
metadata:
  type: project
---

BreezyMac (macOS fan-control app, bundle `org.WhoCo.BreezyMac`) — initial
scaffolding complete and committed 2026-08-16; builds with `make build` and was
**tested on-device (macOS 26)** by the user. Architecture, safety invariants,
and SMC/helper details live in `CLAUDE.md` (authoritative).

**Confirmed working on hardware:** helper install/approval flow (required an app
restart after enabling in Login Items & Extensions), Performance mode sets fans
high immediately, Disabled↔Performance switching, lid-close releases fans + wake
resumes control, live fan-speed reads, and the About tab layout.

**Resolved design decisions (first Q&A round):**
1. **macOS 26 is the only priority.** macOS 25 / 15 are stretch goals, revisited
   only after the app is fully functional on 26.
2. **Silent mode = nice-to-have**, not critical; true 0-RPM explored near
   production.
3. **Status-bar icon** current colored image is fine; aesthetics/animation later.
4. **Portuguese = pt-BR** (was pt-PT).
5. **Disabled** need not unregister the daemon — just fully return control and
   stay inert.

**Bug found in testing + fixed (2026-08-16):** in Adaptive/Performance, opening
the status-bar menu stalled the heartbeat (NSMenu runs a nested event-tracking
run loop; the timer was only in default mode) → watchdog reverted fans after
~6 s. Fixed by registering the tick timer in `.common` run-loop modes and firing
via `MainActor.assumeIsolated`. This is now safety invariant #5 in CLAUDE.md.

**Post-scaffolding work done (2026-08-16):** demand-driven polling (app idles
~0.5–0.8% with UI open, ~0% when Disabled+closed); live approval pickup so
enabling the helper in Login Items no longer needs an app relaunch; re-assert
of fan targets when the XPC connection drops / daemon respawns; Uninstall now
drops to Disabled first (was auto-reinstalling within a tick, so unregister
appeared to do nothing and control resumed on its own). Note: after unregister,
macOS may keep a cosmetic Login-Items row until the app bundle is deleted, but
it should no longer be active. Stale-registration self-heal on rebuild-after-
delete is a possible follow-up (doesn't affect normal in-place `make run`).

**Next up:** Adaptive curve model + editor UX (#3) — user is choosing a
graphing/widget library (looking at what idevtim.chillmac uses) and is
reconsidering whether plain linear interpolation is the right curve shape
(monotone-cubic / eased response under discussion). Also pending: CPU/GPU-usage
inputs to the algorithm, a few unit tests for the pure logic (FanCurve,
SMCDecode). Deferred: Silent 0-RPM, release signing/notarization, Swift 6 mode.
See [[breezymac-reference-projects]].
