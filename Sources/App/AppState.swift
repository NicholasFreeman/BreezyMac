//
//  AppState.swift
//  BreezyMac — App
//
//  The single observable source of truth the UI binds to. Persists the user's
//  operating mode and fan curve; holds live telemetry and helper status that
//  the FanController updates each tick.
//

import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Persisted user intent

    @Published var mode: OperatingMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
            onModeChange?(mode)
        }
    }

    @Published var curveConfig: FanCurveConfig {
        didSet { persistCurve() }
    }

    @Published var automaticConfig: AutomaticConfig {
        didSet { persistAutomatic() }
    }

    @Published var popoverSettings: PopoverSettings {
        didSet { persistPopover() }
    }

    // MARK: Live state (updated by controllers)

    @Published var telemetry = TelemetrySnapshot()
    @Published var helperStatus: HelperStatus = .unknown
    @Published var helperVersion: String? = nil
    @Published var powerSource: PowerSource = .ac
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    /// Rolling telemetry history for charts (oldest first, most recent last).
    @Published var history: [TelemetrySample] = []

    /// Set by FanController so mode changes trigger an immediate apply.
    var onModeChange: ((OperatingMode) -> Void)?

    private let defaults = UserDefaults.standard
    private let historyLimit = 300
    private enum Keys {
        static let mode = "operatingMode"
        static let curve = "fanCurveConfig"
        static let automatic = "automaticConfig"
        static let popover = "popoverSettings"
    }

    private init() {
        if let raw = defaults.string(forKey: Keys.mode), let m = OperatingMode(rawValue: raw) {
            mode = m
        } else {
            mode = .disabled   // safe default: no influence until the user opts in
        }

        if let data = defaults.data(forKey: Keys.curve),
           let cfg = try? JSONDecoder().decode(FanCurveConfig.self, from: data) {
            curveConfig = cfg
        } else {
            curveConfig = .default
        }

        if let data = defaults.data(forKey: Keys.automatic),
           let cfg = try? JSONDecoder().decode(AutomaticConfig.self, from: data) {
            automaticConfig = cfg
        } else {
            automaticConfig = .default
        }

        if let data = defaults.data(forKey: Keys.popover),
           let cfg = try? JSONDecoder().decode(PopoverSettings.self, from: data) {
            popoverSettings = cfg
        } else {
            popoverSettings = .default
        }
    }

    private func persistCurve() {
        if let data = try? JSONEncoder().encode(curveConfig) {
            defaults.set(data, forKey: Keys.curve)
        }
    }

    private func persistAutomatic() {
        if let data = try? JSONEncoder().encode(automaticConfig) {
            defaults.set(data, forKey: Keys.automatic)
        }
    }

    private func persistPopover() {
        if let data = try? JSONEncoder().encode(popoverSettings) {
            defaults.set(data, forKey: Keys.popover)
        }
    }

    /// Append a sample to the rolling history buffer, trimming to the limit.
    func appendHistory(from snapshot: TelemetrySnapshot) {
        history.append(TelemetrySample(time: Date(),
                                       cpuTemp: snapshot.cpuTemp,
                                       gpuTemp: snapshot.gpuTemp,
                                       batteryTemp: snapshot.batteryTemp,
                                       fanRPMs: snapshot.fans.map { $0.actualRPM }))
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }
}
