# BreezyMac

Fan control for Apple-Silicon MacBooks. A status-bar app with four operating
modes and a privileged helper that talks to the SMC — designed so the helper
has **zero influence on your fans whenever the app isn't actively in control**.

> Status: early scaffolding. Local **debug** builds with ad-hoc signing only.

## Modes

| Mode | Behavior |
|------|----------|
| **Disabled** | All fan control returned to macOS. The default; nothing is installed until you pick another mode. |
| **Silent** | Fans held at their lowest speed, regardless of load. |
| **Adaptive** | Fans follow a temperature curve (CPU/GPU/system). |
| **Performance** | Fans held at maximum, regardless of load. |

## Requirements

- macOS 26 (Tahoe) or later, Apple Silicon
- Xcode 26 + toolchain
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```sh
make build   # generate the Xcode project and build (Debug, ad-hoc signed)
make run     # build, then launch — a fan icon appears in the menu bar
make help    # list all targets
```

The project file is generated from `project.yml`; run `make gen` after changing
it. See [CLAUDE.md](CLAUDE.md) for architecture, safety invariants, and the SMC /
helper-install details.

## How it stays safe

- The helper runs a **watchdog**: no heartbeat from the app for a few seconds and
  it hands every fan back to macOS auto — so quit, crash, sleep, or a closed lid
  all release control automatically.
- The app also releases control on sleep, on quit, and whenever you choose
  **Disabled**.

## Architecture

- **App** (`org.WhoCo.BreezyMac`) — unprivileged, status-bar UI, sensor reads.
- **Helper** (`org.WhoCo.BreezyMac.Helper`) — root LaunchDaemon (via
  `SMAppService`), SMC writes over NSXPC. Approve it in **System Settings →
  General → Login Items & Extensions** the first time you enable an active mode.

## License

TBD.
