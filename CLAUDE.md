# CLAUDE.md — BreezyMac

Guidance for working in this repository. Read this first.

## What this is

**BreezyMac** is a macOS fan-control application for Apple-Silicon MacBooks. It
is *exclusively* about system temperatures and fan control — no battery %,
memory, or disk UI. It has two processes:

- **App** (`org.WhoCo.BreezyMac`): unprivileged, status-bar–only agent (no Dock
  icon). A status-bar menu switches modes; an on-demand tabbed window configures
  everything. Reads sensors directly (SMC reads need no root).
- **Helper** (`org.WhoCo.BreezyMac.Helper`): a privileged root LaunchDaemon that
  performs SMC *writes* (fan mode/target). Installed via `SMAppService`,
  reachable only over NSXPC.

Only the app touches the UI; only the helper touches fan writes.

## The four operating modes (the central abstraction)

`OperatingMode` (Sources/Shared/OperatingMode.swift):
- **disabled** — app + helper have zero influence; all control returned to macOS.
  This is the safe default. The helper is not even registered until an engaging
  mode first needs it.
- **silent** — all fans forced to the lowest attainable speed (curve ignored).
- **adaptive** — fans follow the fan curve vs CPU/GPU/system thermals.
- **performance** — all fans forced to maximum (curve ignored).

## Safety invariants (non-negotiable — these are product requirements)

1. **No influence when the UI isn't active.** The app sends a heartbeat every
   `kHelperHeartbeatInterval` (2 s) while any engaging mode is active. The helper
   runs a **watchdog**: if no heartbeat for `kHelperWatchdogTimeout` (6 s) it
   returns every fan to macOS auto on its own. This single mechanism covers app
   quit, crash, sleep, and lid-close (a slept app can't heartbeat).
2. **Release on sleep / lid close.** The app also proactively releases on
   `NSWorkspace.willSleepNotification` and re-asserts on `didWakeNotification`.
3. **Release on quit.** `applicationWillTerminate` → `FanController.shutdown()`
   releases control; the helper additionally releases on XPC invalidation and on
   SIGTERM/SIGINT.
4. **Disabled means disabled.** In `.disabled` the app releases control, stops
   heartbeating, and remains completely inert. (It need not *unregister* the
   daemon — leaving it registered-but-dormant is acceptable as long as control
   is fully returned to macOS.)
5. **The heartbeat timer MUST run in `.common` run-loop modes.** While the
   status-bar `NSMenu` (or any menu/modal panel) is open, AppKit runs a nested
   run loop in event-tracking mode. A timer registered only in the default mode
   stops firing, the heartbeat lapses, and the watchdog reverts fans mid-use.
   `FanController` adds its tick timer via `RunLoop.main.add(t, forMode: .common)`
   and fires synchronously (`MainActor.assumeIsolated`). Do not regress this.

When touching control flow, do not weaken these. The reference apps we derived
from both *lacked* reset-on-quit/sleep handling — that was their worst bug.

## Layout

```
Sources/
  Shared/            compiled into BOTH targets
    OperatingMode.swift  FanCurve.swift  HelperProtocol.swift
    SMC/ SMCTypes.swift  SMCConnection.swift  SMCKeys.swift
  App/               unprivileged UI (AppKit + SwiftUI)
    main.swift  AppDelegate.swift  AppState.swift  HelperClient.swift
    FanController.swift  StatusBarController.swift  ConfigWindowController.swift
    Theme.swift  Views/ConfigView.swift
    Info.plist  BreezyMac.entitlements  Resources/ (icons, Localizable.xcstrings)
  Helper/            privileged daemon (Foundation/IOKit only — no AppKit)
    main.swift  HelperDelegate.swift  HelperService.swift  FanSMC.swift
    Info.plist  Helper.entitlements  LaunchDaemon.plist  Launchd.plist
assets/              production images (organized); source icon: assets/app_icon.png
scripts/             generate-icons.sh, uninstall-helper.sh
project.yml          XcodeGen spec — THE source of truth for the build
Makefile             gen / build / run / clean / icons
```

## Build & run

```
make build     # xcodegen generate + xcodebuild (Debug, ad-hoc signed)
make run       # build, then launch (status-bar item appears; Disabled by default)
make icons     # regenerate icons from assets/app_icon.png
make clean     # remove build/ and the generated .xcodeproj
```

- The `.xcodeproj` is **generated** from `project.yml` and git-ignored. After
  editing `project.yml`, run `make gen`. Never hand-edit the `.xcodeproj`.
- Local **debug builds with ad-hoc signing only** for now (`CODE_SIGN_IDENTITY=-`).
  Release signing/notarization is a later milestone.
- Swift **5 language mode** (`SWIFT_VERSION=5.0`) for now to keep concurrency
  friction low; migrating to Swift 6 mode is a future task.
- **DEBUG builds skip the helper's XPC client code-sign check** (ad-hoc has no
  Team ID). The release path (pinned requirement, audit-token validated) lives
  behind `#if !DEBUG` in HelperDelegate.swift and still needs a real Developer ID.

## Helper install / XPC (how it actually works)

- Install: `SMAppService.daemon(plistName: "org.WhoCo.BreezyMac.Helper.plist")`
  then `register()`. `register()` can throw even when the real outcome is
  "requires approval" — always reconcile against `service.status`, never the
  thrown error. Approval is manual in **System Settings → General → Login Items
  & Extensions** (no admin-password modal).
- Bundle layout the install depends on (built by `project.yml` postCompileScript):
  - daemon executable → `Contents/Library/LaunchServices/org.WhoCo.BreezyMac.Helper`
  - install plist → `Contents/Library/LaunchDaemons/org.WhoCo.BreezyMac.Helper.plist`
    (missing → `SMAppServiceErrorDomain 108`; nothing works, silently)
  - launchd plist embedded in the Mach-O `__TEXT,__launchd_plist` (via `-sectcreate`)
- Connect: `NSXPCConnection(machServiceName: kHelperMachServiceName, options: .privileged)`.
- The mach service name, launchd Label, and helper bundle id are all identical:
  `org.WhoCo.BreezyMac.Helper`.

## SMC notes (fan control crux)

- IOKit `AppleSMC`, `IOServiceOpen(type:0)`, one selector (`kSMCKernelIndex = 2`);
  the op is chosen by `data8` (readKeyInfo=9, readBytes=5, writeBytes=6).
- Read keys: `FNum`, `F{i}Ac/Mn/Mx/Tg`, `F{i}ID`; temps via fallback lists
  (see SMCKeys.swift).
- Write keys: `F{i}Md`/`F{i}md` (0=auto,1=manual), `F{i}Tg` (target), `Ftst`
  (Apple-Silicon unlock gate), `FS! ` (Intel bitmask).
- Apple-Silicon manual-control unlock: probe mode-key case → try direct mode
  write → if needed raise `Ftst`, re-assert mode with **bounded** retries → write
  target encoded per its type (`flt`/`fpe2`). We intentionally avoid the
  reference's multi-second blocking / hundreds of retries.

## Localization

- String Catalog: `Sources/App/Resources/Localizable.xcstrings`. Shipped locales:
  en, en-GB, es, zh-Hans, ko, de, fr, pt-BR (also in `CFBundleLocalizations`).
- Use `String(localized: "key", defaultValue: "English")` in code; add the key +
  translations to the catalog.

## Reference projects (in `Reference/`, git-ignored intent)

- `ShahzaibAli02.Fanny-MacOs-FanControl` — correct modern SMC fan control + fan
  curves, but unstable; **no** reset-on-quit/sleep (its worst flaw), setuid-root
  CLI (a privesc footgun), 40 process-forks/min. We reused its SMC key set +
  Apple-Silicon unlock, rejected its privilege/lifecycle model.
- `idevtim.chillmac` — elegant status-bar UI + a clean `SMAppService`+NSXPC
  privileged-helper install flow; fan control historically broken (missing
  bundle plist → error 108). We reused its install/XPC architecture + UI shape.

Treat `Reference/` and `Reference/assets/` as read-only source material — never
ship from them.

## Resolved design decisions (from the first Q&A round)

- **Deployment target: macOS 26** is the sole priority. macOS 25 / macOS 15 are
  *stretch goals*, revisited only once the app is fully functional on 26. Keep
  the target at 26.0 for now; don't spend effort on back-compat yet.
- **Silent mode** is a *nice-to-have*, not critical. True 0-RPM feasibility on
  M-series will be explored nearer production. For now request 0 and let the SMC
  clamp to each fan's floor.
- **Status-bar icon:** the current colored 18pt image is fine. Aesthetics and
  animation come after the app is functional.
- **Portuguese: pt-BR** (Brazilian) is the supported dialect.
- **Disabled state:** does not need to unregister the daemon — just guarantee it
  fully returns control to macOS and stays inert (invariant #4).

Confirmed working on-device (macOS 26): helper install/approval (needs an app
restart after enabling in Login Items), Performance mode, Disabled↔Performance
switching, lid-close release + wake resume, and live fan-speed reads.

## Still open / next up

- Adaptive-mode curve editor UX and the CPU/GPU-usage inputs to the algorithm.
- Silent 0-RPM investigation (deferred).
- Release signing/notarization + Swift 6 language mode (deferred).
```
