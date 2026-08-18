//
//  AppDelegate.swift
//  BreezyMac — App
//
//  Owns the long-lived controllers. Runs as an accessory (no Dock icon); the
//  only always-on UI is the status-bar item. On termination it hands fan
//  control back to macOS.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = FanController()
    private let actions = ConfigActions()
    private var statusBar: StatusBarController?
    private var configWindow: ConfigWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // belt-and-suspenders with LSUIElement

        wireActions()

        let config = ConfigWindowController(actions: actions)
        configWindow = config

        let bar = StatusBarController()
        bar.onOpenConfiguration = { [weak config] in config?.show() }
        statusBar = bar

        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    private func wireActions() {
        actions.installHelper   = { [weak self] in self?.controller.helper.install() }
        actions.uninstallHelper = { [weak self] in self?.controller.helper.uninstall() }
        actions.openLoginItems  = { [weak self] in self?.controller.helper.openLoginItemsSettings() }
        actions.dumpKeys        = { [weak self] completion in self?.controller.helper.dumpFanKeys(completion: completion) }
    }
}
