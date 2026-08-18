//
//  Theme.swift
//  BreezyMac — App
//
//  Lightweight design tokens. The reference app leans on a translucent, dark,
//  navy-tinted card aesthetic; we keep a small semantic palette here and grow
//  it during the dedicated design pass. Colors are theme-aware via the system.
//

import SwiftUI

enum Theme {
    static let accent = Color.teal

    /// Green → yellow → orange → red ramp for a temperature in °C.
    static func temperatureColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<50:  return .green
        case ..<70:  return .yellow
        case ..<85:  return .orange
        default:     return .red
        }
    }

    /// Accent color per operating mode, matching the status-bar semantics.
    static func modeColor(_ mode: OperatingMode) -> Color {
        switch mode {
        case .disabled:    return .secondary
        case .automatic:   return .teal
        case .adaptive:    return .green
        case .performance: return .orange
        }
    }
}
