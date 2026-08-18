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

    // MARK: Live state (updated by controllers)

    @Published var telemetry = TelemetrySnapshot()
    @Published var helperStatus: HelperStatus = .unknown
    @Published var helperVersion: String? = nil

    /// Set by FanController so mode changes trigger an immediate apply.
    var onModeChange: ((OperatingMode) -> Void)?

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let mode = "operatingMode"
        static let curve = "fanCurveConfig"
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
    }

    private func persistCurve() {
        if let data = try? JSONEncoder().encode(curveConfig) {
            defaults.set(data, forKey: Keys.curve)
        }
    }
}
