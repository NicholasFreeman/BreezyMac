//
//  ConfigWindowController.swift
//  BreezyMac — App
//
//  Hosts the SwiftUI tabbed configuration window inside a plain NSWindow, shown
//  on demand from the status-bar menu. The app stays an accessory (no Dock
//  icon) even while this window is open; we simply activate and key it.
//

import AppKit
import SwiftUI
import ServiceManagement

/// Plain action bridge handed to the SwiftUI views so they can trigger
/// AppKit/helper operations without holding the controllers directly.
@MainActor
final class ConfigActions {
    var installHelper: () -> Void = {}
    var uninstallHelper: () -> Void = {}
    var openLoginItems: () -> Void = {}
    var dumpKeys: (@escaping (String) -> Void) -> Void = { $0("") }

    func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("BreezyMac: launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class ConfigWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let actions: ConfigActions

    /// Fired true when the window is shown and false when it closes, so the
    /// controller can poll telemetry only while the window is on screen.
    var onVisibilityChange: ((Bool) -> Void)?

    init(actions: ConfigActions) {
        self.actions = actions
        super.init()
    }

    func show() {
        if window == nil { makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }

    private func makeWindow() {
        let root = ConfigView(actions: actions).environmentObject(AppState.shared)
        let hosting = NSHostingController(rootView: root)

        let win = NSWindow(contentViewController: hosting)
        win.title = "BreezyMac"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 700, height: 480))
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        window = win
    }
}
