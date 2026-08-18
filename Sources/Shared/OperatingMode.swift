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
    /// All fans forced to their lowest attainable speed, load ignored.
    case silent
    /// Fans driven by the fan curve relative to CPU/GPU/system thermals.
    case adaptive
    /// All fans forced to maximum, load ignored.
    case performance

    /// Whether this mode actively engages the helper (i.e. takes fan control).
    /// `.disabled` is the only mode that must relinquish control entirely.
    var engagesHelper: Bool { self != .disabled }

    /// Localized display name (falls back to the raw value if no catalog entry).
    var displayName: String {
        switch self {
        case .disabled:    return String(localized: "mode.disabled", defaultValue: "Disabled")
        case .silent:      return String(localized: "mode.silent", defaultValue: "Silent")
        case .adaptive:    return String(localized: "mode.adaptive", defaultValue: "Adaptive")
        case .performance: return String(localized: "mode.performance", defaultValue: "Performance")
        }
    }

    /// SF Symbol used in the status-bar menu and configuration UI.
    var symbolName: String {
        switch self {
        case .disabled:    return "moon.zzz"
        case .silent:      return "speaker.slash"
        case .adaptive:    return "thermometer.medium"
        case .performance: return "bolt.fill"
        }
    }
}
