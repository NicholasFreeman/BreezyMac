//
//  ConfigView.swift
//  BreezyMac — App
//
//  The tabbed configuration window. Sections: General (mode + helper), Automatic
//  (anti-throttle setpoints), Curve (Adaptive-mode editor), Popover (live-chart
//  toggles + refresh), and About. Live telemetry now lives in the status-bar
//  popover, so the former Fans and Sensors tabs were removed. This is
//  intentionally a functional-but-minimal scaffold; the elegant visual pass
//  (translucent cards, animations) comes later, informed by the ChillMac look.
//

import SwiftUI
import Charts

struct ConfigView: View {
    @EnvironmentObject var state: AppState
    let actions: ConfigActions

    var body: some View {
        TabView {
            GeneralTab(actions: actions)
                .tabItem { Label(String(localized: "tab.general", defaultValue: "General"), systemImage: "gearshape") }
            AutomaticTab()
                .tabItem { Label(String(localized: "tab.automatic", defaultValue: "Automatic"), systemImage: "gauge.medium") }
            CurveTab()
                .tabItem { Label(String(localized: "tab.curve", defaultValue: "Curve"), systemImage: "chart.xyaxis.line") }
            PopoverTab()
                .tabItem { Label(String(localized: "tab.popover", defaultValue: "Popover"), systemImage: "chart.bar.xaxis") }
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
                setpoint(String(localized: "auto.target", defaultValue: "Start ramping"), value: targetBinding(\.acTargetC, ceiling: \.acCeilingC), range: 50...95)
                setpoint(String(localized: "auto.ceiling", defaultValue: "Maximum by"), value: ceilingBinding(\.acCeilingC, target: \.acTargetC), range: 60...105)
            }
            Section(String(localized: "auto.battery", defaultValue: "On Battery")) {
                setpoint(String(localized: "auto.target", defaultValue: "Start ramping"), value: targetBinding(\.batteryTargetC, ceiling: \.batteryCeilingC), range: 50...100)
                setpoint(String(localized: "auto.ceiling", defaultValue: "Maximum by"), value: ceilingBinding(\.batteryCeilingC, target: \.batteryTargetC), range: 60...110)
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
            Section {
                Button {
                    state.automaticConfig = .default
                } label: {
                    Label(String(localized: "auto.reset", defaultValue: "Reset to Defaults"), systemImage: "arrow.counterclockwise")
                }
                .disabled(state.automaticConfig == .default)
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

    private let minGap: Double = 5

    /// Target binding clamped to stay at least `minGap` below its ceiling.
    private func targetBinding(_ target: WritableKeyPath<AutomaticConfig, Double>,
                               ceiling: WritableKeyPath<AutomaticConfig, Double>) -> Binding<Double> {
        Binding(
            get: { state.automaticConfig[keyPath: target] },
            set: { state.automaticConfig[keyPath: target] = min($0, state.automaticConfig[keyPath: ceiling] - minGap) }
        )
    }

    /// Ceiling binding clamped to stay at least `minGap` above its target.
    private func ceilingBinding(_ ceiling: WritableKeyPath<AutomaticConfig, Double>,
                                target: WritableKeyPath<AutomaticConfig, Double>) -> Binding<Double> {
        Binding(
            get: { state.automaticConfig[keyPath: ceiling] },
            set: { state.automaticConfig[keyPath: ceiling] = max($0, state.automaticConfig[keyPath: target] + minGap) }
        )
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

// MARK: - Popover

private struct PopoverTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section(String(localized: "popover.tempLines", defaultValue: "Temperature Lines")) {
                Toggle(String(localized: "sensor.cpu", defaultValue: "CPU"), isOn: $state.popoverSettings.showCPUTemp)
                Toggle(String(localized: "sensor.gpu", defaultValue: "GPU"), isOn: $state.popoverSettings.showGPUTemp)
                Toggle(String(localized: "sensor.battery", defaultValue: "Battery"), isOn: $state.popoverSettings.showBatteryTemp)
            }
            Section(String(localized: "popover.fanLines", defaultValue: "Fan Speed")) {
                Toggle(String(localized: "popover.showFans", defaultValue: "Show fan speed"), isOn: $state.popoverSettings.showFans)
            }
            Section(String(localized: "popover.indicators", defaultValue: "Header Indicators")) {
                Toggle(String(localized: "popover.indicator.cpu", defaultValue: "CPU temperature"), isOn: $state.popoverSettings.showCPUIndicator)
                Toggle(String(localized: "popover.indicator.gpu", defaultValue: "GPU temperature"), isOn: $state.popoverSettings.showGPUIndicator)
                Toggle(String(localized: "popover.indicator.fan", defaultValue: "Fan speed"), isOn: $state.popoverSettings.showFanIndicator)
            }
            Section(String(localized: "popover.refresh", defaultValue: "Refresh")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "popover.refreshRate", defaultValue: "Chart refresh"))
                        Spacer()
                        Text(String(format: "%.0f s", state.popoverSettings.refreshInterval))
                            .monospacedDigit().foregroundStyle(Theme.accent)
                    }
                    Slider(value: $state.popoverSettings.refreshInterval,
                           in: PopoverSettings.minRefreshInterval...PopoverSettings.maxRefreshInterval,
                           step: 1)
                    Text(String(localized: "popover.refresh.help", defaultValue: "How often the live charts update while the popover is open."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle(String(localized: "popover.background", defaultValue: "Keep history while closed"),
                       isOn: $state.popoverSettings.backgroundSampling)
                    .disabled(true)
                Text(String(localized: "popover.background.help", defaultValue: "Background sampling to keep the charts warm while the popover is closed arrives in a later update."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Curve

private struct CurveTab: View {
    @EnvironmentObject var state: AppState
    @State private var editingSource: PowerSource = .ac

    var body: some View {
        Form {
            Section {
                Text(String(localized: "curve.note", defaultValue: "Adaptive mode drives fans from these curves. The highest resulting speed across enabled curves wins."))
                    .font(.callout).foregroundStyle(.secondary)
                Picker(String(localized: "curve.smoothing", defaultValue: "Smoothing"),
                       selection: $state.curveConfig.interpolation) {
                    ForEach(CurveInterpolation.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker(String(localized: "curve.editing", defaultValue: "Editing"), selection: $editingSource) {
                    Text(PowerSource.ac.displayName).tag(PowerSource.ac)
                    Text(PowerSource.battery.displayName).tag(PowerSource.battery)
                }
                .pickerStyle(.segmented)
            }

            Section(String(localized: "curve.preview", defaultValue: "Preview")) {
                CurvePreview(curves: state.curveConfig.curves(for: editingSource),
                             interpolation: state.curveConfig.interpolation)
                Text(String(localized: "curve.preview.hint", defaultValue: "Solid = active smoothing; dashed = the other, for comparison."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if editingSource == .ac {
                curveEditor($state.curveConfig.ac)
            } else {
                curveEditor($state.curveConfig.battery)
            }

            Section {
                Button {
                    state.curveConfig = .default
                } label: {
                    Label(String(localized: "curve.reset", defaultValue: "Reset to Defaults"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func curveEditor(_ curves: Binding<[FanCurve]>) -> some View {
        ForEach(curves) { $curve in
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
}

/// A read-only preview of the enabled curves for one power source. Each curve is
/// sampled from the model itself (so it exactly reflects the control math) in the
/// active interpolation (solid) plus the alternative one (dashed) for comparison.
private struct CurvePreview: View {
    let curves: [FanCurve]
    let interpolation: CurveInterpolation

    private let domain: ClosedRange<Double> = 30...105

    private struct Sample: Identifiable { let id: Int; let temp: Double; let pct: Double }

    private func samples(_ curve: FanCurve, _ mode: CurveInterpolation) -> [Sample] {
        stride(from: domain.lowerBound, through: domain.upperBound, by: 1).enumerated().map { i, t in
            Sample(id: i, temp: t, pct: curve.speedPercent(forTemperature: t, interpolation: mode))
        }
    }

    private func color(_ source: ThermalSource) -> Color {
        switch source {
        case .cpu:     return PopoverPalette.cpu
        case .gpu:     return PopoverPalette.gpu
        case .battery: return PopoverPalette.battery
        }
    }

    private var enabled: [FanCurve] { curves.filter(\.enabled) }
    private var alternative: CurveInterpolation { interpolation == .linear ? .smooth : .linear }

    var body: some View {
        Group {
            if enabled.isEmpty {
                Text(String(localized: "curve.preview.none", defaultValue: "No curves enabled for this power source."))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(enabled) { curve in
                        // Alternative smoothing — faint dashed, drawn first (behind).
                        ForEach(samples(curve, alternative)) { s in
                            LineMark(x: .value("°C", s.temp), y: .value("%", s.pct),
                                     series: .value("series", "\(curve.id)-alt"))
                                .foregroundStyle(color(curve.source).opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                        // Active smoothing — solid.
                        ForEach(samples(curve, interpolation)) { s in
                            LineMark(x: .value("°C", s.temp), y: .value("%", s.pct),
                                     series: .value("series", "\(curve.id)-active"))
                                .foregroundStyle(color(curve.source))
                        }
                        // Control points.
                        ForEach(curve.points) { p in
                            PointMark(x: .value("°C", p.temperature), y: .value("%", p.speedPercent))
                                .foregroundStyle(color(curve.source))
                                .symbolSize(26)
                        }
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 15)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v))°") }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v))%") }
                        }
                    }
                }
                .frame(height: 170)
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
