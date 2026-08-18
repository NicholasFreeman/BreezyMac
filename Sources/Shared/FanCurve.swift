//
//  FanCurve.swift
//  BreezyMac — Shared
//
//  The Adaptive-mode fan curve model. A curve maps a driving temperature to a
//  fan-speed percentage by interpolating between sorted control points with a
//  monotone cubic spline (smooth, and guaranteed not to dip or overshoot).
//  Multiple curves (one per sensor) can be active; the engine takes the MAX
//  resulting percentage across curves ("highest safety wins"), following the
//  Fanny rules-engine semantics but in a cleaner model.
//
//  Curves are power-source aware — a separate set for AC and battery, mirroring
//  Automatic's setpoints.
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

    /// Interpolate the requested fan-speed percentage for a given temperature
    /// using a monotone cubic spline. Below the first point → first point's
    /// percent; above the last point → last point's percent.
    func speedPercent(forTemperature temp: Double) -> Double {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        if temp <= first.temperature { return first.speedPercent }
        if temp >= last.temperature { return last.speedPercent }
        // Cubic needs ≥ 3 points to differ from linear; below that, use linear.
        let raw = sorted.count >= 3 ? FanCurve.monotoneCubicValue(sorted, at: temp)
                                    : FanCurve.linearValue(sorted, at: temp)
        return min(100, max(0, raw))
    }

    // MARK: Interpolators (assume `sorted` has ≥ 2 points and first.x < x < last.x)

    private static func linearValue(_ sorted: [CurvePoint], at x: Double) -> Double {
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            if x >= a.temperature && x <= b.temperature {
                let span = b.temperature - a.temperature
                guard span > 0 else { return max(a.speedPercent, b.speedPercent) }
                let ratio = (x - a.temperature) / span
                return a.speedPercent + ratio * (b.speedPercent - a.speedPercent)
            }
        }
        return sorted.last?.speedPercent ?? 0
    }

    /// Monotone cubic Hermite interpolation (Fritsch–Carlson tangents). Preserves
    /// monotonicity of the data, so the curve never overshoots or dips between
    /// control points — important for a fan curve that should only ever rise.
    private static func monotoneCubicValue(_ sorted: [CurvePoint], at x: Double) -> Double {
        let n = sorted.count
        let xs = sorted.map(\.temperature)
        let ys = sorted.map(\.speedPercent)

        // Secant slopes between successive points.
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let h = xs[i + 1] - xs[i]
            delta[i] = h > 0 ? (ys[i + 1] - ys[i]) / h : 0
        }

        // Initial tangents: endpoints use the adjacent secant; interior points the
        // average, flattened to 0 at local extrema to preserve monotonicity.
        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        for i in 1..<(n - 1) {
            m[i] = (delta[i - 1] * delta[i] <= 0) ? 0 : (delta[i - 1] + delta[i]) / 2
        }

        // Fritsch–Carlson limiter: keep each (α, β) within the monotone circle.
        for i in 0..<(n - 1) {
            if delta[i] == 0 {
                m[i] = 0; m[i + 1] = 0
            } else {
                let a = m[i] / delta[i]
                let b = m[i + 1] / delta[i]
                let s = a * a + b * b
                if s > 9 {
                    let t = 3.0 / s.squareRoot()
                    m[i] = t * a * delta[i]
                    m[i + 1] = t * b * delta[i]
                }
            }
        }

        // Evaluate the Hermite basis on the interval containing x.
        var k = 0
        for i in 0..<(n - 1) where x >= xs[i] && x <= xs[i + 1] { k = i; break }
        let h = xs[k + 1] - xs[k]
        let t = (x - xs[k]) / h
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * ys[k] + h10 * h * m[k] + h01 * ys[k + 1] + h11 * h * m[k + 1]
    }
}

/// The complete Adaptive-mode configuration: a curve set per power source.
struct FanCurveConfig: Codable, Equatable, Sendable {
    var ac: [FanCurve]
    var battery: [FanCurve]

    /// The curve set that applies for a given power source.
    func curves(for source: PowerSource) -> [FanCurve] {
        source == .battery ? battery : ac
    }

    /// Sensible starting curves: CPU and GPU curves enabled per source (cooler on
    /// AC, quieter/hotter on battery). GPU is on by default so a GPU-bound load is
    /// protected out of the box — the max across enabled curves wins.
    static var `default`: FanCurveConfig {
        FanCurveConfig(
            ac: [
                FanCurve(source: .cpu, enabled: true, points: [
                    CurvePoint(temperature: 40, speedPercent: 0),
                    CurvePoint(temperature: 55, speedPercent: 25),
                    CurvePoint(temperature: 70, speedPercent: 55),
                    CurvePoint(temperature: 85, speedPercent: 90),
                    CurvePoint(temperature: 95, speedPercent: 100),
                ]),
                FanCurve(source: .gpu, enabled: true, points: [
                    CurvePoint(temperature: 45, speedPercent: 0),
                    CurvePoint(temperature: 60, speedPercent: 25),
                    CurvePoint(temperature: 75, speedPercent: 55),
                    CurvePoint(temperature: 90, speedPercent: 100),
                ]),
            ],
            battery: [
                FanCurve(source: .cpu, enabled: true, points: [
                    CurvePoint(temperature: 50, speedPercent: 0),
                    CurvePoint(temperature: 65, speedPercent: 20),
                    CurvePoint(temperature: 80, speedPercent: 50),
                    CurvePoint(temperature: 92, speedPercent: 85),
                    CurvePoint(temperature: 100, speedPercent: 100),
                ]),
                FanCurve(source: .gpu, enabled: true, points: [
                    CurvePoint(temperature: 55, speedPercent: 0),
                    CurvePoint(temperature: 70, speedPercent: 25),
                    CurvePoint(temperature: 85, speedPercent: 55),
                    CurvePoint(temperature: 95, speedPercent: 100),
                ]),
            ]
        )
    }

    /// Resolve the target fan-speed fraction (0...1) for a telemetry snapshot on a
    /// given power source, taking the maximum across that source's enabled curves.
    func targetFraction(for snapshot: TelemetrySnapshot, source: PowerSource) -> Double {
        var best = 0.0
        for curve in curves(for: source) where curve.enabled {
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
