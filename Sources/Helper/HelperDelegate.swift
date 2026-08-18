//
//  HelperDelegate.swift
//  BreezyMac — Helper (privileged)
//
//  NSXPCListener delegate. Accepts connections from the app and wires each to a
//  fresh HelperService. On connection invalidation it releases fan control — a
//  safety net for the case where the app crashes without a clean handoff.
//
//  In DEBUG builds (ad-hoc signed, hacking from source) the client code-signing
//  check is skipped. In release builds the peer MUST satisfy a pinned code
//  requirement, validated against its audit token (not its PID).
//

import Foundation

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        #if !DEBUG
        guard HelperDelegate.isValidClient(newConnection) else {
            NSLog("BreezyMac helper: rejected XPC client failing code requirement")
            return false
        }
        #endif

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.invalidationHandler = {
            // App went away without releasing — hand fans back to macOS.
            FanControlEngine.shared.release()
        }
        newConnection.resume()
        return true
    }

    #if !DEBUG
    // TODO: replace the certificate leaf clause with the real Developer ID once
    // we move past ad-hoc signing (tracked for the release-build milestone).
    private static let clientRequirement =
        "identifier \"org.WhoCo.BreezyMac\" and anchor apple generic"

    private static func isValidClient(_ connection: NSXPCConnection) -> Bool {
        // Read the peer's audit token defensively (KVC-exposed, may be absent).
        guard let tokenData = auditToken(of: connection) else { return false }

        var code: SecCode?
        let attrs = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let clientCode = code else { return false }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(clientRequirement as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }

        return SecCodeCheckValidity(clientCode, [], req) == errSecSuccess
    }

    private static func auditToken(of connection: NSXPCConnection) -> Data? {
        guard connection.responds(to: NSSelectorFromString("auditToken")),
              let value = connection.value(forKey: "auditToken") as? NSValue else { return nil }
        var token = audit_token_t()
        value.getValue(&token)
        return withUnsafeBytes(of: &token) { Data($0) }
    }
    #endif
}
