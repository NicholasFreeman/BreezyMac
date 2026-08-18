//
//  HelperClient.swift
//  BreezyMac — App
//
//  App-side management of the privileged helper: install/registration via
//  SMAppService (macOS 13+), the NSXPC connection, and typed call wrappers.
//
//  Design notes carried over from the ChillMac reference:
//   • register() can throw even when the outcome is really "requires approval",
//     so we always reconcile against service.status rather than the thrown error.
//   • .ready is asserted only after a live XPC round-trip, never merely because
//     SMAppService reports .enabled.
//   • SMAppService daemons are approved by the user in System Settings →
//     General → Login Items & Extensions; there is no admin password modal.
//

import Foundation
import ServiceManagement

enum HelperStatus: Equatable {
    case unknown
    case notInstalled
    case installing
    case requiresApproval
    case ready
    case failed(String)
}

@MainActor
final class HelperClient {
    private let service = SMAppService.daemon(plistName: "org.WhoCo.BreezyMac.Helper.plist")
    private var connection: NSXPCConnection?

    var onStatusChange: ((HelperStatus) -> Void)?
    var onVersion: ((String) -> Void)?

    private func setStatus(_ status: HelperStatus) { onStatusChange?(status) }

    // MARK: Registration / install

    /// Register the daemon and reconcile to a HelperStatus. Safe to call
    /// repeatedly (idempotent once enabled).
    func install() {
        setStatus(.installing)
        if service.status == .enabled {
            verifyThenReady()
            return
        }
        do {
            try service.register()
        } catch {
            NSLog("BreezyMac: SMAppService.register() threw (\(error.localizedDescription)); deciding from status")
        }
        switch service.status {
        case .enabled:
            verifyThenReady()
        case .requiresApproval:
            setStatus(.requiresApproval)
        case .notRegistered, .notFound:
            setStatus(.failed("Helper could not be registered (status: \(statusName(service.status)))."))
        @unknown default:
            setStatus(.failed("Unexpected helper status: \(service.status.rawValue)."))
        }
    }

    /// Remove the daemon entirely (used by an explicit "Uninstall Helper").
    func uninstall() {
        disconnect()
        try? service.unregister()
        setStatus(.notInstalled)
    }

    func refreshStatus() {
        switch service.status {
        case .enabled:          setStatus(.ready)      // caller may downgrade after a failed ping
        case .requiresApproval: setStatus(.requiresApproval)
        case .notRegistered:    setStatus(.notInstalled)
        case .notFound:         setStatus(.notInstalled)
        @unknown default:       setStatus(.unknown)
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func statusName(_ s: SMAppService.Status) -> String {
        switch s {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown(\(s.rawValue))"
        }
    }

    // MARK: XPC connection

    private func proxy(_ errorHandler: @escaping (Error) -> Void) -> HelperProtocol? {
        let conn: NSXPCConnection
        if let existing = connection {
            conn = existing
        } else {
            conn = NSXPCConnection(machServiceName: kHelperMachServiceName, options: .privileged)
            conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            conn.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            conn.interruptionHandler = {
                NSLog("BreezyMac: helper XPC connection interrupted")
            }
            conn.resume()
            connection = conn
        }
        return conn.remoteObjectProxyWithErrorHandler(errorHandler) as? HelperProtocol
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: Verified readiness

    /// Ping the helper; only on a reply do we declare .ready.
    private func verifyThenReady() {
        var completed = false
        let finish: (HelperStatus) -> Void = { [weak self] status in
            guard !completed else { return }
            completed = true
            self?.setStatus(status)
        }

        guard let helper = proxy({ error in
            Task { @MainActor in finish(.failed("Helper unreachable: \(error.localizedDescription)")) }
        }) else {
            finish(.failed("Could not create XPC proxy."))
            return
        }

        helper.getVersion { [weak self] version in
            Task { @MainActor in
                self?.onVersion?(version)
                finish(.ready)
            }
        }

        // Hard timeout guarding against a proxy that never replies nor errors.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            finish(.failed("Helper did not respond within 5s."))
        }
    }

    // MARK: Typed operations

    func heartbeat() {
        proxy({ _ in })?.heartbeat { _ in }
    }

    func applyFanTargets(_ targets: [Int], completion: ((Bool, String?) -> Void)? = nil) {
        guard let helper = proxy({ error in
            Task { @MainActor in completion?(false, error.localizedDescription) }
        }) else {
            completion?(false, "No helper proxy")
            return
        }
        helper.applyFanTargets(targets) { ok, err in
            Task { @MainActor in completion?(ok, err) }
        }
    }

    func releaseControl(completion: ((Bool, String?) -> Void)? = nil) {
        guard let helper = proxy({ error in
            Task { @MainActor in completion?(false, error.localizedDescription) }
        }) else {
            completion?(false, "No helper proxy")
            return
        }
        helper.releaseControl { ok, err in
            Task { @MainActor in completion?(ok, err) }
        }
    }

    func dumpFanKeys(completion: @escaping (String) -> Void) {
        guard let helper = proxy({ error in
            Task { @MainActor in completion("error: \(error.localizedDescription)") }
        }) else {
            completion("error: no helper proxy")
            return
        }
        helper.dumpFanKeys { text in
            Task { @MainActor in completion(text) }
        }
    }
}
