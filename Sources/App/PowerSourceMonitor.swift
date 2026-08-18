//
//  PowerSourceMonitor.swift
//  BreezyMac — App
//
//  Reports whether the machine is on AC or battery and notifies on change, via
//  the public IOKit power-sources API. Used to switch Automatic setpoints (and,
//  later, the Adaptive curves) when the user plugs/unplugs.
//

import Foundation
import IOKit.ps

@MainActor
final class PowerSourceMonitor {
    var onChange: ((PowerSource) -> Void)?
    private var runLoopSource: CFRunLoopSource?

    /// Current providing power source.
    func current() -> PowerSource {
        guard let info = IOPSCopyPowerSourcesInfo() else { return .ac }
        let blob = info.takeRetainedValue()
        guard let typeCF = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() else { return .ac }
        // "Battery Power" → battery; "AC Power"/"UPS Power" → treated as AC.
        return (typeCF as String == kIOPSBatteryPowerValue) ? .battery : .ac
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            // Fires on the main run loop (where the source is scheduled).
            MainActor.assumeIsolated { monitor.onChange?(monitor.current()) }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            NSLog("BreezyMac: could not create power-source notification source")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }
}
