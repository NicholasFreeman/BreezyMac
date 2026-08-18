//
//  AutomaticController.swift
//  BreezyMac — App
//
//  The Automatic (anti-throttle) control law. Given the latest temperatures,
//  the system thermal state, the power source, and the tunables, it returns a
//  fan-speed fraction (0...1).
//
//  Strategy:
//   • Proportional ramp between `target` and `ceiling` on the hottest of the
//     CPU/GPU sensors.
//   • An anticipation term on dT/dt so the fans lead a fast spike.
//   • A thermal-pressure override: whenever macOS reports `.serious`/`.critical`
//     thermal state (the only public proxy for throttling on Apple Silicon) or a
//     sensor reaches the ceiling, command 100% and hold briefly.
//   • Asymmetric smoothing: ramp up immediately, decay slowly to avoid hunting.
//

import Foundation

@MainActor
final class AutomaticController {
    private var lastTemp: Double?
    private var lastTime: Date?
    private var lastFraction: Double = 0
    private var overrideHoldUntil: Date?

    /// °C/s of temperature rise that maps to full anticipation boost.
    private let rateScaleCPerSec = 2.0
    /// How long to hold maximum after thermal pressure clears.
    private let overrideHoldSeconds: TimeInterval = 5
    /// Maximum downward change in fraction per second (slow decay).
    private let decayPerSecond = 0.15
    /// Fallback interval used for decay before we have two samples.
    private let assumedInterval: TimeInterval = 2.0

    func reset() {
        lastTemp = nil
        lastTime = nil
        lastFraction = 0
        overrideHoldUntil = nil
    }

    func fraction(cpu: Double?,
                  gpu: Double?,
                  thermalState: ProcessInfo.ThermalState,
                  source: PowerSource,
                  config: AutomaticConfig,
                  now: Date) -> Double {
        guard let temp = [cpu, gpu].compactMap({ $0 }).max() else {
            return lastFraction   // no reading — hold steady rather than guess
        }

        let target = config.target(for: source)
        let ceiling = max(config.ceiling(for: source), target + 1)

        // Proportional term.
        let proportional = clamp((temp - target) / (ceiling - target), 0, 1)

        // Anticipation term on the rate of rise.
        var boost = 0.0
        if let lastTemp, let lastTime {
            let dt = now.timeIntervalSince(lastTime)
            if dt > 0 {
                let rate = (temp - lastTemp) / dt
                if rate > 0 {
                    boost = clamp(config.spikeResponse * (rate / rateScaleCPerSec), 0, 1)
                }
            }
        }

        var base = clamp(proportional + boost, 0, 1)

        // Thermal-pressure / ceiling override → maximum, held briefly.
        let underPressure = thermalState == .serious || thermalState == .critical || temp >= ceiling
        if underPressure {
            overrideHoldUntil = now.addingTimeInterval(overrideHoldSeconds)
        }
        if let hold = overrideHoldUntil, now < hold {
            base = 1.0
        } else {
            overrideHoldUntil = nil
        }

        // Asymmetric smoothing: rise now, decay slowly.
        var result = base
        if base < lastFraction {
            let dt = lastTime.map { now.timeIntervalSince($0) } ?? assumedInterval
            result = max(base, lastFraction - decayPerSecond * dt)
        }

        lastTemp = temp
        lastTime = now
        lastFraction = result
        return result
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
