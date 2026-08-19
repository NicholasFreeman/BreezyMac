---
name: breezymac-versioning
description: Where BreezyMac's version lives and how to pick the next number (git tags lead the code strings)
metadata:
  type: project
---

Bumping the version touches **three** places (keep them in sync):
- `project.yml` — `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` (the App
  `Info.plist` reads both via `$(…)`, so it needs no edit). Run `make gen` after
  editing project.yml; the `.xcodeproj` is generated + git-ignored.
- `Sources/Helper/Info.plist` — hardcodes `CFBundleVersion` +
  `CFBundleShortVersionString`.
- `Sources/App/Views/ConfigView.swift` — `appVersion`'s `?? "x.y.z"` fallback.

**The next version number comes from `git tag -l`, not the version strings.**
Tags can run ahead of the code: on 2026-08-18 `v0.6.1` was already tagged (on the
README-beta commit `7f2740c`) while every version string still read `0.6.0`. So
the localization/popover patch went `0.6.0 → 0.6.2`, skipping the already-consumed
`0.6.1`. Always check `git tag` before choosing the next number.

Tag convention is `vMAJOR.MINOR.PATCH` (e.g. `v0.6.0`), but tagging appears to be
done manually by the user — don't create tags unless asked. See
[[breezymac-phase-and-open-questions]] and [[breezymac-user-preferences]].
