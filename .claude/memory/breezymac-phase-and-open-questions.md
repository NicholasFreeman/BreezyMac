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

**Next up:** Adaptive curve-editor UX + CPU/GPU-usage inputs; then (deferred)
Silent 0-RPM, release signing/notarization, Swift 6 mode. See
[[breezymac-reference-projects]].
