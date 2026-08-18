//
//  ConfigView.swift
//  BreezyMac — App
//
//  The tabbed configuration window. Sections: General (mode + helper), Fans
//  (live telemetry), Curve (Adaptive-mode editor), Sensors, and About. This is
//  intentionally a functional-but-minimal scaffold; the elegant visual pass
//  (translucent cards, animations) comes later, informed by the ChillMac look.
//

import SwiftUI

struct ConfigView: View {
    @EnvironmentObject var state: AppState
    let actions: ConfigActions

    var body: some View {
        TabView {
            GeneralTab(actions: actions)
                .tabItem { Label(String(localized: "tab.general", defaultValue: "General"), systemImage: "gearshape") }
            AutomaticTab()
                .tabItem { Label(String(localized: "tab.automatic", defaultValue: "Automatic"), systemImage: "gauge.medium") }
            FansTab()
                .tabItem { Label(String(localized: "tab.fans", defaultValue: "Fans"), systemImage: "fanblades") }
            CurveTab()
                .tabItem { Label(String(localized: "tab.curve", defaultValue: "Curve"), systemImage: "chart.xyaxis.line") }
            SensorsTab()
                .tabItem { Label(String(localized: "tab.sensors", defaultValue: "Sensors"), systemImage: "thermometer.medium") }
            AboutTab()
                .tabItem { Label(String(localized: "tab.about", defaultValue: "About"), systemImage: "info.circle") }
        }
        .frame(minWidth: 520, minHeight: 420)
        .padding()
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    let actions: ConfigActions
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section(String(localized: "general.mode", defaultValue: "Operating Mode")) {
                Picker("", selection: $state.mode) {
                    ForEach(OperatingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Label(modeDescription, systemImage: state.mode.symbolName)
                    .foregroundStyle(Theme.modeColor(state.mode))
                    .font(.callout)
            }

            Section(String(localized: "general.helper", defaultValue: "Fan Control Helper")) {
                LabeledContent(String(localized: "general.status", defaultValue: "Status")) {
                    Text(helperStatusText).foregroundStyle(helperStatusColor)
                }
                HStack {
                    Button(String(localized: "general.install", defaultValue: "Install / Repair")) { actions.installHelper() }
                    if case .requiresApproval = state.helperStatus {
                        Button(String(localized: "general.approve", defaultValue: "Open Login Items…")) { actions.openLoginItems() }
                    }
                    Spacer()
                    Button(String(localized: "general.uninstall", defaultValue: "Uninstall"), role: .destructive) { actions.uninstallHelper() }
                }
                .font(.callout)
            }

            Section(String(localized: "general.startup", defaultValue: "Startup")) {
                Toggle(String(localized: "general.launchAtLogin", defaultValue: "Launch BreezyMac at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in actions.setLaunchAtLogin(newValue) }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = actions.isLaunchAtLoginEnabled() }
    }

    private var modeDescription: String {
        switch state.mode {
        case .disabled:    return String(localized: "desc.disabled", defaultValue: "Fan control is fully returned to macOS.")
        case .automatic:   return String(localized: "desc.automatic", defaultValue: "Fans ramp automatically to keep temperatures below the throttle threshold.")
        case .adaptive:    return String(localized: "desc.adaptive", defaultValue: "Fans follow your curve based on temperature.")
        case .performance: return String(localized: "desc.performance", defaultValue: "Fans held at maximum, regardless of load.")
        }
    }

    private var helperStatusText: String {
        switch state.helperStatus {
        case .unknown:          return String(localized: "helper.unknown", defaultValue: "Unknown")
        case .notInstalled:     return String(localized: "helper.notInstalled", defaultValue: "Not installed")
        case .installing:       return String(localized: "helper.installing", defaultValue: "Installing…")
        case .requiresApproval: return String(localized: "helper.requiresApproval", defaultValue: "Needs approval in System Settings")
        case .ready:            return String(localized: "helper.ready", defaultValue: "Ready")
        case .failed(let m):    return String(localized: "helper.failed", defaultValue: "Failed") + ": \(m)"
        }
    }

    private var helperStatusColor: Color {
        switch state.helperStatus {
        case .ready: return .green
        case .requiresApproval, .installing: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
}

// MARK: - Automatic

private struct AutomaticTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                Text(String(localized: "auto.note", defaultValue: "Automatic holds temperatures below the throttle threshold: fans stay quiet until the target, ramp toward the ceiling, and jump to maximum under thermal pressure. Setpoints differ per power source."))
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent(String(localized: "auto.currentSource", defaultValue: "Current power"), value: state.powerSource.displayName)
                LabeledContent(String(localized: "auto.thermal", defaultValue: "Thermal state")) {
                    Text(thermalStateName(state.thermalState)).foregroundStyle(thermalStateColor(state.thermalState))
                }
            }
            Section(String(localized: "auto.ac", defaultValue: "On External Power")) {
                setpoint(String(localized: "auto.target", defaultValue: "Start ramping"), value: $state.automaticConfig.acTargetC, range: 50...95)
                setpoint(String(localized: "auto.ceiling", defaultValue: "Maximum by"), value: $state.automaticConfig.acCeilingC, range: 60...105)
            }
            Section(String(localized: "auto.battery", defaultValue: "On Battery")) {
                setpoint(String(localized: "auto.target", defaultValue: "Start ramping"), value: $state.automaticConfig.batteryTargetC, range: 50...100)
                setpoint(String(localized: "auto.ceiling", defaultValue: "Maximum by"), value: $state.automaticConfig.batteryCeilingC, range: 60...110)
            }
            Section(String(localized: "auto.spikeSection", defaultValue: "Spike Response")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "auto.spike", defaultValue: "Anticipation"))
                        Spacer()
                        Text(String(format: "%.0f%%", state.automaticConfig.spikeResponse * 100)).monospacedDigit().foregroundStyle(Theme.accent)
                    }
                    Slider(value: $state.automaticConfig.spikeResponse, in: 0...1)
                    Text(String(localized: "auto.spike.help", defaultValue: "Higher values ramp the fans earlier when temperature is rising quickly."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setpoint(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.0f°C", value.wrappedValue)).monospacedDigit().foregroundStyle(Theme.accent)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}

private func thermalStateName(_ s: ProcessInfo.ThermalState) -> String {
    switch s {
    case .nominal:  return String(localized: "thermal.nominal", defaultValue: "Nominal")
    case .fair:     return String(localized: "thermal.fair", defaultValue: "Fair")
    case .serious:  return String(localized: "thermal.serious", defaultValue: "Serious")
    case .critical: return String(localized: "thermal.critical", defaultValue: "Critical")
    @unknown default: return "—"
    }
}

private func thermalStateColor(_ s: ProcessInfo.ThermalState) -> Color {
    switch s {
    case .nominal:  return .green
    case .fair:     return .yellow
    case .serious:  return .orange
    case .critical: return .red
    @unknown default: return .secondary
    }
}

// MARK: - Fans

private struct FansTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.telemetry.fans.isEmpty {
                ContentUnavailableView(String(localized: "fans.none", defaultValue: "No fans detected"),
                                       systemImage: "fanblades",
                                       description: Text(String(localized: "fans.none.detail", defaultValue: "Sensor data will appear here once available.")))
            } else {
                List(state.telemetry.fans) { fan in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(fan.name).font(.headline)
                            Spacer()
                            Text("\(fan.actualRPM) RPM").monospacedDigit().foregroundStyle(Theme.accent)
                        }
                        ProgressView(value: fanFraction(fan))
                        HStack {
                            Text("min \(fan.minRPM)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("target \(fan.targetRPM)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("max \(fan.maxRPM)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func fanFraction(_ fan: FanReading) -> Double {
        let span = Double(max(1, fan.maxRPM - fan.minRPM))
        return min(1, max(0, Double(fan.actualRPM - fan.minRPM) / span))
    }
}

// MARK: - Curve

private struct CurveTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Text(String(localized: "curve.note", defaultValue: "Adaptive mode drives fans from these curves. The highest resulting speed across enabled curves wins."))
                .font(.callout).foregroundStyle(.secondary)

            ForEach($state.curveConfig.curves) { $curve in
                Section(curve.source.displayName) {
                    Toggle(String(localized: "curve.enabled", defaultValue: "Enabled"), isOn: $curve.enabled)
                    ForEach($curve.points) { $point in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(String(format: "%.0f°C", point.temperature)).monospacedDigit()
                                Spacer()
                                Text(String(format: "%.0f%%", point.speedPercent)).monospacedDigit().foregroundStyle(Theme.accent)
                            }
                            Slider(value: $point.speedPercent, in: 0...100, step: 5)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sensors

private struct SensorsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section(String(localized: "sensors.temps", defaultValue: "Temperatures")) {
                tempRow(String(localized: "sensor.cpu", defaultValue: "CPU"), state.telemetry.cpuTemp)
                tempRow(String(localized: "sensor.gpu", defaultValue: "GPU"), state.telemetry.gpuTemp)
                tempRow(String(localized: "sensor.battery", defaultValue: "Battery"), state.telemetry.batteryTemp)
            }
            Section(String(localized: "sensors.system", defaultValue: "System")) {
                LabeledContent(String(localized: "sensors.power", defaultValue: "Power source"), value: state.powerSource.displayName)
                LabeledContent(String(localized: "sensors.thermal", defaultValue: "Thermal state")) {
                    Text(thermalStateName(state.thermalState)).foregroundStyle(thermalStateColor(state.thermalState))
                }
            }
            Section {
                Text(String(localized: "sensors.usageNote", defaultValue: "CPU/GPU utilization inputs for the adaptive algorithm will be surfaced here in a later iteration."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func tempRow(_ label: String, _ value: Double?) -> some View {
        LabeledContent(label) {
            if let v = value {
                Text(String(format: "%.1f°C", v)).monospacedDigit().foregroundStyle(Theme.temperatureColor(v))
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            LabeledContent(String(localized: "about.app", defaultValue: "Application"), value: "BreezyMac \(appVersion)")
            LabeledContent(String(localized: "about.bundle", defaultValue: "Bundle ID"), value: "org.WhoCo.BreezyMac")
            LabeledContent(String(localized: "about.helper", defaultValue: "Helper"), value: state.helperVersion ?? "—")
            LabeledContent(String(localized: "about.mach", defaultValue: "Mach service"), value: kHelperMachServiceName)
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }
}
