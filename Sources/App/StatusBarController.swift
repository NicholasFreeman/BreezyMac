//
//  StatusBarController.swift
//  BreezyMac — App
//
//  The always-visible status-bar item: a quick mode switcher, a compact live
//  readout, and access to the configuration window. This is the only UI shown
//  during normal operation (no Dock icon — see Info.plist LSUIElement).
//

import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let state = AppState.shared
    private var cancellables = Set<AnyCancellable>()

    var onOpenConfiguration: (() -> Void)?

    private var modeItems: [NSMenuItem] = []
    private let readoutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        configureButton()
        buildMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Keep the status-bar glyph/checkmarks in step with mode changes.
        state.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshDynamicState() }
            .store(in: &cancellables)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(named: "MenuBarIcon") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false   // colored source icon; revisit (template) in design pass
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "BreezyMac")
        }
        button.toolTip = "BreezyMac"
    }

    private func buildMenu() {
        let title = NSMenuItem(title: "BreezyMac", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        for (index, mode) in OperatingMode.allCases.enumerated() {
            let item = NSMenuItem(title: mode.displayName, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil)
            menu.addItem(item)
            modeItems.append(item)
        }

        menu.addItem(.separator())
        readoutItem.isEnabled = false
        menu.addItem(readoutItem)
        menu.addItem(.separator())

        let config = NSMenuItem(title: String(localized: "menu.openConfiguration", defaultValue: "Open Configuration…"),
                                action: #selector(openConfiguration), keyEquivalent: ",")
        config.target = self
        menu.addItem(config)

        let quit = NSMenuItem(title: String(localized: "menu.quit", defaultValue: "Quit BreezyMac"),
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func selectMode(_ sender: NSMenuItem) {
        let modes = OperatingMode.allCases
        guard sender.tag >= 0, sender.tag < modes.count else { return }
        state.mode = modes[sender.tag]
    }

    @objc private func openConfiguration() {
        onOpenConfiguration?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshDynamicState()
    }

    private func refreshDynamicState() {
        let modes = OperatingMode.allCases
        for (index, item) in modeItems.enumerated() {
            item.state = (modes[index] == state.mode) ? .on : .off
        }
        readoutItem.title = readoutText()
    }

    private func readoutText() -> String {
        let t = state.telemetry
        var parts: [String] = []
        if let cpu = t.cpuTemp {
            parts.append(String(format: "CPU %.0f°C", cpu))
        }
        if let fan = t.fans.first {
            parts.append("\(fan.actualRPM) RPM")
        }
        if parts.isEmpty { return String(localized: "menu.noReadings", defaultValue: "Reading sensors…") }
        return parts.joined(separator: "   ·   ")
    }
}
