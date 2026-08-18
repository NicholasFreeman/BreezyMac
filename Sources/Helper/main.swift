//
//  main.swift
//  BreezyMac — Helper (privileged LaunchDaemon)
//
//  Entry point for the root daemon. Publishes the XPC mach service and runs
//  forever. launchd starts it on-demand when the app connects to the mach
//  service, and may stop it when idle. Signal handlers guarantee a graceful
//  hand-back of fan control to macOS on teardown.
//

import Foundation

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: kHelperMachServiceName)
listener.delegate = delegate
listener.resume()

// Non-capturing C-compatible handlers: return fans to auto, then exit.
signal(SIGTERM) { _ in HelperService.cleanupOnExit(); exit(0) }
signal(SIGINT)  { _ in HelperService.cleanupOnExit(); exit(0) }

NSLog("BreezyMac helper \(kHelperVersion) started; listening on \(kHelperMachServiceName)")
RunLoop.current.run()
