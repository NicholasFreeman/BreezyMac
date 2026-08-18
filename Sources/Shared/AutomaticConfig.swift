//
//  AutomaticConfig.swift
//  BreezyMac — Shared
//
//  Tunables for Automatic (anti-throttle) mode. The goal of Automatic is to
//  hold CPU/GPU temperatures below the throttle threshold with margin: fans stay
//  quiet until temperature approaches `target`, ramp proportionally toward
//  `ceiling`, respond early to fast temperature spikes, and go to maximum under
//  measured thermal pressure. Setpoints differ per power source so the machine
//  can run quieter/hotter on battery.
//

import Foundation

struct AutomaticConfig: Codable, Sendable, Equatable {
    /// °C at which fans begin ramping on AC power.
    var acTargetC: Double
    /// °C at which fans reach maximum on AC power (also a hard ceiling).
    var acCeilingC: Double
    /// °C at which fans begin ramping on battery power.
    var batteryTargetC: Double
    /// °C at which fans reach maximum on battery power.
    var batteryCeilingC: Double
    /// 0...1 anticipation gain applied to the rate of temperature rise, so the
    /// fans lead a spike rather than chase it.
    var spikeResponse: Double

    func target(for source: PowerSource) -> Double {
        source == .battery ? batteryTargetC : acTargetC
    }

    func ceiling(for source: PowerSource) -> Double {
        source == .battery ? batteryCeilingC : acCeilingC
    }

    /// Conservative-cool on AC, quieter/hotter on battery. Anticipation defaults
    /// gentle (0.15) — a calm first-run feel that still holds temperatures; power
    /// users can raise it for a snappier response.
    static var `default`: AutomaticConfig {
        AutomaticConfig(acTargetC: 80, acCeilingC: 95,
                        batteryTargetC: 90, batteryCeilingC: 100,
                        spikeResponse: 0.15)
    }
}
