---
name: breezymac-reference-projects
description: What to reuse vs avoid from the two BreezyMac reference projects (Fanny, ChillMac)
metadata:
  type: reference
---

Two reference projects under `Reference/` (read-only source material — never
ship from them):

- **`ShahzaibAli02.Fanny-MacOs-FanControl`** — CORRECT modern SMC fan control +
  fan curves, but unstable. Reuse: SMC key set (`FNum`, `F{i}Ac/Mn/Mx/Tg/Md`,
  `Ftst`, `FS! `), Apple-Silicon `Ftst` unlock sequence, temp fallback lists,
  rules-engine (threshold + linear curve, max-wins). AVOID: setuid-root CLI
  (privesc footgun), fork-per-command IPC (~40/min), multi-second blocking +
  hundreds of SMC retries, and — its worst flaw — **no reset on quit/sleep**.

- **`idevtim.chillmac`** — elegant status-bar UI + clean `SMAppService`+NSXPC
  privileged-helper install flow; fan control historically broken (bundle was
  missing `Contents/Library/LaunchDaemons/…plist` → `SMAppServiceErrorDomain
  108`). Reuse: install/XPC architecture, bundle layout, `Theme` token approach,
  translucent-card UI aesthetic. Note its client-identity pinning is duplicated
  in 3 places (helper `SMAuthorizedClients`, app `SMPrivilegedExecutables`,
  delegate requirement) — must all change together when we get a Developer ID.

BreezyMac's key improvement over both: the app heartbeat + helper watchdog that
guarantees fan control reverts to macOS the moment the app stops pinging.
See [[breezymac-phase-and-open-questions]].
