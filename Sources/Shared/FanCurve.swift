//
//  FanCurve.swift
//  BreezyMac — Shared
//
//  The Adaptive-mode fan curve model. A curve maps a driving temperature to a
//  fan-speed percentage via piecewise-linear interpolation between sorted
//  control points. Multiple curves (one per sensor) can be active; the engine
//  takes the MAX resulting percentage across curves ("highest safety wins"),
//  following the Fanny rules-engine semantics but in a cleaner model.
//

import Foundation

/// Which temperature sensor drives a curve.
enum ThermalSource: String, CaseIterable, Codable, Sendable {
    case cpu
    case gpu
    case battery

    var displayName: String {
        switch self {
        case .cpu:     return String(localized: "sensor.cpu", defaultValue: "CPU")
        case .gpu:     return String(localized: "sensor.gpu", defaultValue: "GPU")
        case .battery: return String(localized: "sensor.battery", defaultValue: "Battery")
        }
    }
}

/// A single control point: at `temperature` °C, request `speedPercent` (0–100).
struct CurvePoint: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var temperature: Double   // °C
    var speedPercent: Double   // 0...100

    init(temperature: Double, speedPercent: Double) {
        self.temperature = temperature
        self.speedPercent = speedPercent
    }
}

/// A fan curve bound to one thermal source.
struct FanCurve: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var source: ThermalSource
    var enabled: Bool
    var points: [CurvePoint]

    init(source: ThermalSource, enabled: Bool = true, points: [CurvePoint]) {
        self.source = source
        self.enabled = enabled
        self.points = points
    }

    /// Interpolate the requested fan-speed percentage for a given temperature.
    /// Below the first point → first point's percent; above the last point →
    /// last point's percent; between → linear interpolation.
    func speedPercent(forTemperature temp: Double) -> Double {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard let first = sorted.first else { return 0 }
        guard let last = sorted.last else { return 0 }
        if temp <= first.temperature { return first.speedPercent }
        if temp >= last.temperature { return last.speedPercent }

        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            if temp >= a.temperature && temp <= b.temperature {
                let span = b.temperature - a.temperature
                guard span > 0 else { return max(a.speedPercent, b.speedPercent) }
                let ratio = (temp - a.temperature) / span
                return a.speedPercent + ratio * (b.speedPercent - a.speedPercent)
            }
        }
        return last.speedPercent
    }
}

/// The complete Adaptive-mode configuration.
struct FanCurveConfig: Codable, Equatable, Sendable {
    var curves: [FanCurve]

    /// A sensible starting configuration: a single CPU-driven curve.
    static var `default`: FanCurveConfig {
        FanCurveConfig(curves: [
            FanCurve(source: .cpu, enabled: true, points: [
                CurvePoint(temperature: 40, speedPercent: 0),
                CurvePoint(temperature: 55, speedPercent: 25),
                CurvePoint(temperature: 70, speedPercent: 55),
                CurvePoint(temperature: 85, speedPercent: 90),
                CurvePoint(temperature: 95, speedPercent: 100),
            ])
        ])
    }

    /// Resolve the target fan-speed fraction (0...1) for a telemetry snapshot,
    /// taking the maximum across all enabled curves.
    func targetFraction(for snapshot: TelemetrySnapshot) -> Double {
        var best = 0.0
        for curve in curves where curve.enabled {
            let temp: Double?
            switch curve.source {
            case .cpu:     temp = snapshot.cpuTemp
            case .gpu:     temp = snapshot.gpuTemp
            case .battery: temp = snapshot.batteryTemp
            }
            guard let t = temp else { continue }
            best = max(best, curve.speedPercent(forTemperature: t) / 100.0)
        }
        return min(1.0, max(0.0, best))
    }
}
