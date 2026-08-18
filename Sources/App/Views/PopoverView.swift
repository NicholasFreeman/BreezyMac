//
//  PopoverView.swift
//  BreezyMac — App
//
//  The status-bar popover: a compact mode switcher, toggleable live text
//  indicators, and two STACKED live charts sharing one synchronized time axis —
//  temperatures (°C) on top, fan speed (RPM) below. Deliberately not a single
//  dual-y-axis chart: two measures of different scale read as two charts.
//
//  Data comes from AppState.history (a rolling buffer that accrues while the UI
//  is visible); a fixed window keeps the point count — and render cost — trivial.
//

import SwiftUI
import Charts

/// Okabe–Ito colorblind-safe categorical palette. Each series has a FIXED color
/// keyed to its identity, so toggling one series never repaints the others.
enum PopoverPalette {
    static let cpu     = Color(red: 0.835, green: 0.369, blue: 0.0)   // vermillion
    static let gpu     = Color(red: 0.0,   green: 0.447, blue: 0.698) // blue
    static let battery = Color(red: 0.0,   green: 0.620, blue: 0.451) // bluish green

    private static let fanRamp: [Color] = [
        Color(red: 0.337, green: 0.706, blue: 0.914), // sky blue
        Color(red: 0.800, green: 0.475, blue: 0.655), // reddish purple
        Color(red: 0.902, green: 0.624, blue: 0.0),   // orange
    ]
    static func fan(_ index: Int) -> Color { fanRamp[index % fanRamp.count] }
}

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    let onOpenConfiguration: () -> Void
    let onQuit: () -> Void

    /// Fixed rolling window shown on the charts (a few minutes keeps it legible
    /// and cheap to render).
    private let windowSeconds: TimeInterval = 5 * 60

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            header
            modePicker
            if anyIndicatorOn { indicatorRow }
            LiveCharts(samples: windowed,
                       settings: state.popoverSettings,
                       fans: state.telemetry.fans,
                       window: windowSeconds)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        // Hug the content vertically so NSHostingController reports the popover's
        // true height. Without this the view expands to the proposed height, the
        // popover over-sizes, and it either flips off the top of the screen (tall)
        // or floats below the icon with a gap (short).
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("BreezyMac").font(.headline)
            Spacer()
            Image(systemName: state.powerSource == .ac ? "bolt.fill" : "battery.100")
                .foregroundStyle(.secondary)
                .help(state.powerSource.displayName)
        }
    }

    private var modePicker: some View {
        Picker("", selection: $state.mode) {
            ForEach(OperatingMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Indicators

    private var anyIndicatorOn: Bool {
        let s = state.popoverSettings
        return s.showCPUIndicator || s.showGPUIndicator || s.showFanIndicator
    }

    private var indicatorRow: some View {
        let s = state.popoverSettings
        let t = state.telemetry
        return HStack(spacing: 16) {
            if s.showCPUIndicator {
                tempIndicator(String(localized: "sensor.cpu", defaultValue: "CPU"), t.cpuTemp)
            }
            if s.showGPUIndicator {
                tempIndicator(String(localized: "sensor.gpu", defaultValue: "GPU"), t.gpuTemp)
            }
            if s.showFanIndicator, let fan = t.fans.first {
                HStack(spacing: 4) {
                    Image(systemName: "fanblades").foregroundStyle(.secondary)
                    Text("\(fan.actualRPM)").monospacedDigit()
                    Text("RPM").foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func tempIndicator(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            if let v = value {
                Text(String(format: "%.0f°", v)).monospacedDigit()
                    .foregroundStyle(Theme.temperatureColor(v))
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button(String(localized: "menu.openConfiguration", defaultValue: "Open Configuration…")) {
                onOpenConfiguration()
            }
            Spacer()
            Button(String(localized: "menu.quit", defaultValue: "Quit BreezyMac")) {
                onQuit()
            }
        }
        .font(.callout)
    }

    // MARK: Windowing

    /// The tail of history within the fixed display window.
    private var windowed: [TelemetrySample] {
        guard let last = state.history.last else { return [] }
        let cutoff = last.time.addingTimeInterval(-windowSeconds)
        return state.history.filter { $0.time >= cutoff }
    }
}

// MARK: - Charts

/// A flattened chart point tagged with its series name for color-by-series.
private struct SeriesPoint: Identifiable {
    let id: Int
    let series: String
    let time: Date
    let value: Double
}

/// The two stacked charts. Both use the same x-scale domain, so the time axis is
/// synchronized; only the lower chart draws x-axis labels (they read as shared).
private struct LiveCharts: View {
    let samples: [TelemetrySample]
    let settings: PopoverSettings
    let fans: [FanReading]
    let window: TimeInterval

    var body: some View {
        VStack(spacing: 6) {
            if showTempChart { tempChart }
            if settings.showFans { fanChart }
        }
    }

    /// The upper chart is shown only when at least one temperature line is on.
    private var showTempChart: Bool {
        settings.showCPUTemp || settings.showGPUTemp || settings.showBatteryTemp
    }

    // Localized series names (also legend + color-scale keys).
    private var cpuName: String { String(localized: "sensor.cpu", defaultValue: "CPU") }
    private var gpuName: String { String(localized: "sensor.gpu", defaultValue: "GPU") }
    private var batteryName: String { String(localized: "sensor.battery", defaultValue: "Battery") }
    private func fanName(_ i: Int) -> String {
        String(localized: "popover.fan", defaultValue: "Fan \(i + 1)")
    }

    /// The right edge of both charts — "now". Discrete (last sample time) so the
    /// axis steps with each refresh rather than sliding continuously.
    private var axisEnd: Date { samples.last?.time ?? Date() }

    private var xDomain: ClosedRange<Date> {
        axisEnd.addingTimeInterval(-window)...axisEnd
    }

    /// Fixed tick positions at one-minute steps back from `axisEnd`. Because both
    /// the domain and these ticks are anchored to `axisEnd`, the labels stay put
    /// ("now" at the right, "5m" at the left) while the data scrolls underneath —
    /// rather than the marks drifting left and relabeling as the window slides.
    private var xTicks: [Date] {
        stride(from: 0.0, through: window, by: 60).map { axisEnd.addingTimeInterval(-$0) }
    }

    // MARK: Temperatures

    private var tempPoints: [SeriesPoint] {
        var pts: [SeriesPoint] = []
        var id = 0
        for s in samples {
            if settings.showCPUTemp, let v = s.cpuTemp {
                pts.append(SeriesPoint(id: id, series: cpuName, time: s.time, value: v)); id += 1
            }
            if settings.showGPUTemp, let v = s.gpuTemp {
                pts.append(SeriesPoint(id: id, series: gpuName, time: s.time, value: v)); id += 1
            }
            if settings.showBatteryTemp, let v = s.batteryTemp {
                pts.append(SeriesPoint(id: id, series: batteryName, time: s.time, value: v)); id += 1
            }
        }
        return pts
    }

    private var tempScale: (domain: [String], range: [Color]) {
        var d: [String] = []; var r: [Color] = []
        if settings.showCPUTemp { d.append(cpuName); r.append(PopoverPalette.cpu) }
        if settings.showGPUTemp { d.append(gpuName); r.append(PopoverPalette.gpu) }
        if settings.showBatteryTemp { d.append(batteryName); r.append(PopoverPalette.battery) }
        return (d, r)
    }

    private var tempYDomain: ClosedRange<Double> {
        let maxV = tempPoints.map(\.value).max() ?? 80
        let top = min(110, max(80, (maxV / 5).rounded(.up) * 5 + 5))
        return 20...top
    }

    private var tempChart: some View {
        Chart(tempPoints) { p in
            LineMark(x: .value("Time", p.time), y: .value("°C", p.value))
                .foregroundStyle(by: .value("Sensor", p.series))
                .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(domain: tempScale.domain, range: tempScale.range)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: tempYDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))°") }
                }
            }
        }
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .frame(height: 118)
        .overlay { if tempPoints.isEmpty { placeholder } }
    }

    // MARK: Fans

    private var fanCount: Int { max(fans.count, samples.last?.fanRPMs.count ?? 0) }

    private var fanPoints: [SeriesPoint] {
        guard settings.showFans else { return [] }
        var pts: [SeriesPoint] = []
        var id = 0
        for s in samples {
            for (i, rpm) in s.fanRPMs.enumerated() {
                pts.append(SeriesPoint(id: id, series: fanName(i), time: s.time, value: Double(rpm))); id += 1
            }
        }
        return pts
    }

    private var fanScale: (domain: [String], range: [Color]) {
        guard settings.showFans, fanCount > 0 else { return ([], []) }
        var d: [String] = []; var r: [Color] = []
        for i in 0..<fanCount { d.append(fanName(i)); r.append(PopoverPalette.fan(i)) }
        return (d, r)
    }

    private var fanYDomain: ClosedRange<Double> {
        let boundMax = Double(fans.map(\.maxRPM).max() ?? 0)
        let observed = fanPoints.map(\.value).max() ?? 0
        let top = max(boundMax, observed, 1000)
        return 0...(top * 1.05)
    }

    private var fanChart: some View {
        Chart(fanPoints) { p in
            LineMark(x: .value("Time", p.time), y: .value("RPM", p.value))
                .foregroundStyle(by: .value("Fan", p.series))
                .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(domain: fanScale.domain, range: fanScale.range)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: fanYDomain)
        .chartXAxis {
            AxisMarks(values: xTicks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        let m = Int((axisEnd.timeIntervalSince(d) / 60).rounded())
                        Text(m == 0 ? String(localized: "popover.now", defaultValue: "now") : "\(m)m")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v >= 1000 ? String(format: "%.0fk", v / 1000) : String(format: "%.0f", v))
                    }
                }
            }
        }
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .frame(height: 108)
        .overlay { if fanPoints.isEmpty { placeholder } }
    }

    private var placeholder: some View {
        Text(String(localized: "popover.collecting", defaultValue: "Collecting data…"))
            .font(.caption).foregroundStyle(.secondary)
    }
}
