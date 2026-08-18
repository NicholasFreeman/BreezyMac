<p align="center">
  <img src="assets/app_icon.png" alt="BreezyMac" width="128" height="128">
</p>

<h1 align="center">BreezyMac</h1>

<p align="center"><em>Keep your Apple-Silicon MacBook cool and quick — a menu-bar fan controller that fights thermal throttling.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026-blue" alt="Platform: macOS 26">
  <img src="https://img.shields.io/badge/chip-Apple%20Silicon-black" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/status-alpha-orange" alt="Status: alpha">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License: MIT">
</p>

---

## What is BreezyMac?

Your MacBook is quietly conservative about its fans. Under a sustained load it
tends to stay hushed a little too long, lets the chip get hot, and then
*throttles* — quietly slowing itself down to cool off. If you've ever watched a
long export, build, or game get slower and slower while the laptop turns into a
griddle, that's the moment BreezyMac was built for.

BreezyMac lives in your menu bar and spins the fans up a bit sooner, so your Mac
can hold its performance instead of backing off. It's deliberately focused: this
is an app about **temperatures and fans**, nothing else — no battery percentages,
no memory graphs, no disk widgets. Click the menu-bar icon and you get a clean
popover with live temperature and fan charts and a one-tap mode switch. That's it.

It's also careful. BreezyMac only ever *borrows* control of your fans, and it
hands that control straight back to macOS the moment it isn't actively looking
after them — when you quit, sleep, close the lid, or switch it off.

## Features

- **Four simple modes** — pick one from the menu bar:
  - **Disabled** — hands everything back to macOS (the safe default).
  - **Automatic** — the star of the show. Fans ramp on their own to keep temperatures
    below the throttle point. One gentle "Anticipation" slider is usually all the
    tuning you'll ever touch.
  - **Adaptive** — draw your own fan curves if you like to be hands-on.
  - **Performance** — fans to the max, for when you just want maximum cooling.
- **Knows if you're plugged in** — Automatic and Adaptive keep separate settings
  for wall power vs. battery, so your Mac can run cooler on AC and quieter on battery.
- **Live charts** — a menu-bar popover with stacked temperature (°C) and fan-speed
  (RPM) charts sharing one timeline, plus toggleable at-a-glance readouts.
- **Watches the real hot spot** — reads the hottest CPU and GPU die sensors, so it
  reacts to the temperature that actually causes throttling.
- **Stays out of your way** — no Dock icon, and it idles at essentially zero CPU
  when there's nothing to do.
- **Speaks your language** — English, British English, Spanish, French, German,
  Brazilian Portuguese, Korean, and Simplified Chinese.

## How it works

BreezyMac is two small pieces working together:

- An **unprivileged menu-bar app** that shows the UI and reads the sensors
  (reading temperatures and fan speeds needs no special permissions).
- A tiny **privileged helper** that performs the actual fan changes (that part
  *does* need root). The helper is installed on demand the first time you pick a
  mode that needs it, stays dormant otherwise, and — importantly — reverts every
  fan back to macOS on its own if the app ever stops checking in. That safety net
  covers quitting, crashing, sleeping, and closing the lid.

## Requirements

- An **Apple-Silicon Mac** (M-series). BreezyMac is designed and tested for these.
- **macOS 26** — the primary supported target. Older macOS may work but isn't a goal yet.
- **Xcode 26** (which includes the macOS 26 SDK) and its Command Line Tools.
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** to generate the Xcode project:
  ```sh
  brew install xcodegen
  ```
- `make` (installed with the Xcode Command Line Tools).

### Dependencies

There are **no third-party runtime dependencies**. BreezyMac is built entirely on
Apple's own frameworks — AppKit, SwiftUI, Swift Charts, IOKit, and
ServiceManagement. The only build-time tool it relies on is XcodeGen, which turns
[`project.yml`](project.yml) into the Xcode project.

## Building from source

```sh
git clone https://github.com/NicholasFreeman/BreezyMac.git
cd BreezyMac
make build     # generates the Xcode project, then builds a Debug, ad-hoc-signed app
make run       # build and launch — a fan icon appears in the menu bar
```

`make run` starts BreezyMac in **Disabled** mode, so it has zero influence until
you opt in.

### Other useful targets

| Command                | What it does                                             |
| ---------------------- | ------------------------------------------------------- |
| `make gen`             | Regenerate the Xcode project from `project.yml`         |
| `make icons`           | Rebuild icon assets from `assets/app_icon.png`          |
| `make open-loginitems` | Jump to System Settings → Login Items (to approve the helper) |
| `make dump-helper`     | Print the helper's current launchd state (for debugging) |
| `make clean`           | Remove the generated project and build products         |
| `make help`            | List all targets                                        |

### Notes for the curious

- The `.xcodeproj` is **generated** from `project.yml` and is git-ignored. Edit
  `project.yml` and run `make gen` — never hand-edit the project file.
- Builds are **Debug, ad-hoc signed** (`CODE_SIGN_IDENTITY=-`) for now. Proper
  Developer ID signing and notarization are a later milestone.
- The project builds in Swift 5 language mode today.
- Curious about the architecture and the safety invariants? They're documented in
  [`CLAUDE.md`](CLAUDE.md).

## First run: enabling fan control

The first time you choose **Automatic**, **Adaptive**, or **Performance**,
BreezyMac needs to install its privileged helper so it can change fan speeds:

1. Pick an engaging mode from the menu-bar popover.
2. macOS will ask you to approve the helper in **System Settings → General →
   Login Items & Extensions** (no admin password prompt — just a toggle). The
   `make open-loginitems` shortcut takes you straight there.
3. After enabling it, **quit and reopen BreezyMac** if fan control doesn't engage
   right away.

Once approved, switching modes is instant.

## A quick word of caution

BreezyMac is **alpha** software. It deliberately overrides your Mac's normal fan
behavior, and while it's built to always return control to macOS when it isn't
actively in charge, running your fans differently from the factory settings is
something you're choosing to do. Use it at your own discretion, keep an eye on
your temperatures at first, and switch to **Disabled** any time to hand everything
back to macOS.

## Status & license

This is an early **alpha** — serviceable and useful day to day, with more polish
(a nicer visual design, release signing) still to come.

BreezyMac is released under the [MIT License](LICENSE.md) — © 2026 Nicholas
Freeman. You're free to use, modify, and distribute it; see the license for the
full terms.
