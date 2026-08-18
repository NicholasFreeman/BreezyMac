//
//  PopoverSettings.swift
//  BreezyMac — App
//
//  User preferences for the status-bar popover: which temperature/fan series
//  and text indicators are shown on the live charts, and how often those charts
//  refresh. App-only UI state (the helper never sees this) — persisted to
//  UserDefaults via AppState.
//

import Foundation

struct PopoverSettings: Codable, Equatable {
    // Temperature series drawn on the upper chart.
    var showCPUTemp: Bool = true
    var showGPUTemp: Bool = true
    var showBatteryTemp: Bool = false

    // Fan speed series drawn on the lower chart (one line per fan).
    var showFans: Bool = true

    // Compact text indicators in the header row above the charts.
    var showCPUIndicator: Bool = true
    var showGPUIndicator: Bool = true
    var showFanIndicator: Bool = true

    // Seconds between live chart refreshes. This subsamples the fixed 2 s control
    // tick, so it can never be faster than the heartbeat cadence (a safety floor).
    var refreshInterval: Double = 2.0

    // Placeholder for a later task: keep history warm while the popover is closed
    // by sampling at a low rate in the background. Wired but inert for now.
    var backgroundSampling: Bool = false

    static let `default` = PopoverSettings()

    /// The refresh cadence can never be faster than the control tick / heartbeat.
    static let minRefreshInterval: Double = 2.0
    static let maxRefreshInterval: Double = 10.0
}
