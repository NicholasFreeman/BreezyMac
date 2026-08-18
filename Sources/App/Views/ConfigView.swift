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
        case .silent:      return String(localized: "desc.silent", defaultValue: "Fans held at their lowest speed, regardless of load.")
        case .adaptive:    return String(localized: "desc.adaptive", defaultValue: "Fans follow the curve based on temperature.")
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
