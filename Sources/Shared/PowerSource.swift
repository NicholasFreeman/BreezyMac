//
//  PowerSource.swift
//  BreezyMac — Shared
//
//  Whether the machine is running on external (AC) power or the battery.
//  Automatic setpoints and (later) the Adaptive curves switch on this.
//

import Foundation

enum PowerSource: String, Codable, Sendable, Equatable {
    case ac
    case battery

    var displayName: String {
        switch self {
        case .ac:      return String(localized: "power.ac", defaultValue: "External Power")
        case .battery: return String(localized: "power.battery", defaultValue: "Battery")
        }
    }
}
