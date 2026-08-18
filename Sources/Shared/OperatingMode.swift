//
//  OperatingMode.swift
//  BreezyMac — Shared
//
//  The four top-level operating modes that govern the entire application.
//  Shared between app and helper so both sides speak the same vocabulary.
//

import Foundation

enum OperatingMode: String, CaseIterable, Codable, Sendable {
    /// App and helper have no influence; all fan control is returned to macOS.
    case disabled
    /// Fans ramp automatically to hold temperatures below the throttle threshold
    /// (power-source aware). The recommended, no-tuning mode.
    case automatic
    /// Fans driven by user-defined curves (per power source).
    case adaptive
    /// All fans forced to maximum, load ignored.
    case performance

    /// Whether this mode actively engages the helper (i.e. takes fan control).
    /// `.disabled` is the only mode that must relinquish control entirely.
    var engagesHelper: Bool { self != .disabled }

    /// Modes whose control decisions depend on live temperatures, so a tick must
    /// read them even when no UI is visible.
    var needsTemperature: Bool { self == .automatic || self == .adaptive }

    /// Localized display name (falls back to the raw value if no catalog entry).
    var displayName: String {
        switch self {
        case .disabled:    return String(localized: "mode.disabled", defaultValue: "Disabled")
        case .automatic:   return String(localized: "mode.automatic", defaultValue: "Automatic")
        case .adaptive:    return String(localized: "mode.adaptive", defaultValue: "Adaptive")
        case .performance: return String(localized: "mode.performance", defaultValue: "Performance")
        }
    }

    /// SF Symbol used in the status-bar menu and configuration UI.
    var symbolName: String {
        switch self {
        case .disabled:    return "moon.zzz"
        case .automatic:   return "gauge.medium"
        case .adaptive:    return "thermometer.medium"
        case .performance: return "bolt.fill"
        }
    }
}
