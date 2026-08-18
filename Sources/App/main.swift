//
//  main.swift
//  BreezyMac — App
//
//  Manual AppKit entry point (no @main / storyboard) so we retain full control
//  over activation policy and the status-bar lifecycle.
//

import AppKit

// Program entry already runs on the main thread, so we can assume main-actor
// isolation to construct the (main-actor-isolated) delegate and run the app.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
