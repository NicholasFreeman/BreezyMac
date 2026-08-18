//
//  StatusBarController.swift
//  BreezyMac — App
//
//  The always-visible status-bar item. Clicking it toggles a SwiftUI popover
//  (mode switcher + live charts + Open Configuration / Quit) — this is the only
//  UI shown during normal operation (no Dock icon — see Info.plist LSUIElement).
//
//  We use an NSPopover rather than an NSMenu so the readout can host live Swift
//  Charts. A popover is non-modal, so unlike a menu it does not spin a nested
//  event-tracking run loop; the heartbeat timer keeps firing normally (safety
//  invariant #5), and FanController is told when it opens/closes so telemetry is
//  polled only while it is on screen.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let state = AppState.shared
    private var cancellables = Set<AnyCancellable>()

    var onOpenConfiguration: (() -> Void)?
    /// Fired true just before the popover displays and false when it closes, so
    /// the controller polls telemetry only while it is on screen.
    var onPopoverVisibilityChange: ((Bool) -> Void)?

    override init() {
        super.init()
        configureButton()
        configurePopover()

        // Keep the status-bar glyph in step with mode changes.
        state.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshButton() }
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
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func configurePopover() {
        let root = PopoverView(
            onOpenConfiguration: { [weak self] in
                self?.closePopover()
                self?.onOpenConfiguration?()
            },
            onQuit: { NSApp.terminate(nil) }
        ).environmentObject(state)

        popover.contentViewController = NSHostingController(rootView: root)
        popover.behavior = .transient      // closes when the user clicks away
        popover.animates = true
        popover.delegate = self
    }

    // MARK: Actions

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // An accessory (LSUIElement) app that isn't active positions the popover
        // relative to the wrong context — it can land off the top of the screen.
        // Activating first anchors it correctly below the icon and also lets the
        // SwiftUI controls (segmented picker, sliders) receive key/mouse events.
        NSApp.activate(ignoringOtherApps: true)
        // `.minY` = the icon's bottom edge, so the popover drops down from it and
        // centers horizontally on the icon.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    // MARK: NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        onPopoverVisibilityChange?(true)   // start polling / seed fresh telemetry
    }

    func popoverDidClose(_ notification: Notification) {
        onPopoverVisibilityChange?(false)
    }

    private func refreshButton() {
        // Placeholder for a mode-tinted glyph in the later design pass; the
        // popover itself already reflects the active mode.
        statusItem.button?.toolTip = "BreezyMac — \(state.mode.displayName)"
    }
}
