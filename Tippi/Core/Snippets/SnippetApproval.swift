import CryptoKit
import Foundation
import os

private let approvalLog = Logger(subsystem: "com.tippi.app", category: "snippet-approval")

/// Consent record for one imported snippet that can run a shell command.
///
/// Before the import feature, consent was anchored in the Espanso file itself:
/// a hash of the file was stored, and every load re-compared it, so an edit
/// after approval re-prompted. Once snippets live in Tippi's own store that
/// anchor is gone — the store is a plain JSON file any process running as the
/// user can rewrite. Re-using a stored hash would verify nothing.
///
/// The replacement is a MAC over the approved content, keyed by a secret that
/// lives in the Keychain rather than next to the data. Rewriting the store is
/// then not enough: a forged entry also needs the key, which macOS guards and
/// prompts about. See docs/SECURE-DESIGN-espanso-import.md.
struct SnippetApproval: Codable, Equatable {
    /// Base64 MAC over (trigger, command). Not a hash of the file.
    let mac: String
    let approvedAt: Date
}

/// Signs and verifies shell-snippet approvals.
///
/// Every entry point fails closed. A missing key, an unreadable Keychain, a
/// malformed MAC — all of them mean "not approved", never "assume fine". The
/// cost of a false negative is one extra consent prompt; the cost of a false
/// positive is arbitrary command execution.
enum SnippetApprovalSigner {
    /// Default Keychain service. Overridable so tests can use a throwaway
    /// service instead of touching the real one — deleting the production key
    /// during a test run would silently revoke every approval on this Mac.
    static let defaultService = "com.tippi.app.snippet-approval"
    private static let keychainAccount = "hmac-key-v1"
    private static let keyByteCount = 32

    // MARK: - Public API

    /// MAC for a snippet's approvable content. `nil` means the key was
    /// unavailable — callers must treat that as "cannot approve", not as
    /// "approve without a MAC".
    static func sign(trigger: String, command: String, service: String = defaultService) -> SnippetApproval? {
        guard let key = loadOrCreateKey(service: service) else {
            approvalLog.error("cannot sign approval — Keychain key unavailable")
            return nil
        }
        guard let mac = mac(trigger: trigger, command: command, key: key) else { return nil }
        return SnippetApproval(mac: mac, approvedAt: Date())
    }

    /// True only when `approval` was issued by this machine for exactly this
    /// trigger and command. Any deviation — edited command, swapped trigger,
    /// hand-written store entry, missing key — returns false.
    static func verify(_ approval: SnippetApproval?, trigger: String, command: String, service: String = defaultService) -> Bool {
        guard let approval else { return false }
        guard let key = loadKey(service: service) else {
            // Deliberately does not create a key here: a verification path that
            // can mint a fresh key would let an attacker who deleted the
            // Keychain item re-sign whatever they want.
            approvalLog.error("cannot verify approval — Keychain key unavailable")
            return false
        }
        guard let expected = mac(trigger: trigger, command: command, key: key),
              let expectedData = Data(base64Encoded: expected),
              let actualData = Data(base64Encoded: approval.mac)
        else { return false }
        // Constant-time comparison. Timing leaks matter little for a local
        // single-user app, but a MAC compared with `==` is the kind of detail
        // that gets copied into a context where it does matter.
        return constantTimeEquals(expectedData, actualData)
    }

    /// Removes the signing key. Every existing approval becomes unverifiable,
    /// so every shell snippet needs fresh consent. Intended for an explicit
    /// "revoke all snippet permissions" action, not for routine cleanup.
    @discardableResult
    static func revokeAllApprovals(service: String = defaultService) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        // Before evaluating the result: a cached copy would keep verifying
        // approvals the user just revoked, for the rest of the session.
        invalidateKeyCache(service: service)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - MAC

    private static func mac(trigger: String, command: String, key: SymmetricKey) -> String? {
        // Length-prefixed fields, not concatenation: signing "ab" + "c" and
        // "a" + "bc" must not collide, or a crafted trigger could carry part
        // of an approved command and change what actually runs.
        var message = Data()
        for field in [trigger, command] {
            guard let bytes = field.data(using: .utf8) else { return nil }
            withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { message.append(contentsOf: $0) }
            message.append(bytes)
        }
        let code = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(code).base64EncodedString()
    }

    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    // MARK: - Keychain

    /// Process-lifetime cache of the HMAC key, keyed by service.
    ///
    /// `verify` runs inside `activeTriggers()`, which the keystroke monitor
    /// calls on **every keypress**. Each uncached call is a real
    /// `SecItemCopyMatching` — measured at 1.09 ms on this machine, so ten
    /// approved shell snippets cost ~11 ms of the event tap per character
    /// typed. That is latency the user feels as the whole system lagging.
    ///
    /// The security property this protects is "another process cannot read the
    /// key", and that is enforced by the Keychain ACL, not by how often we ask.
    /// The key is already resident in process memory for the duration of any
    /// verify; caching extends that window, it does not create it. Stored per
    /// service so the throwaway services the tests use can never collide with
    /// the production one.
    private static let keyCacheLock = NSLock()
    nonisolated(unsafe) private static var keyCache: [String: SymmetricKey] = [:]

    /// Drops cached keys. Must be called whenever the stored key changes,
    /// otherwise a revoked key keeps verifying for the rest of the session.
    private static func invalidateKeyCache(service: String) {
        keyCacheLock.lock()
        keyCache[service] = nil
        keyCacheLock.unlock()
    }

    private static func loadKey(service: String) -> SymmetricKey? {
        keyCacheLock.lock()
        let cached = keyCache[service]
        keyCacheLock.unlock()
        if let cached { return cached }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == keyByteCount else {
            if status != errSecItemNotFound {
                approvalLog.error("Keychain read failed, status=\(status, privacy: .public)")
            }
            return nil
        }
        // Only successes are cached. A failed read (locked Keychain, missing
        // item) must stay retryable — caching `nil` would turn a transient
        // condition into a permanent one for the rest of the session.
        let key = SymmetricKey(data: data)
        keyCacheLock.lock()
        keyCache[service] = key
        keyCacheLock.unlock()
        return key
    }

    private static func loadOrCreateKey(service: String) -> SymmetricKey? {
        if let existing = loadKey(service: service) { return existing }

        var bytes = Data(count: keyByteCount)
        let generated = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, keyByteCount, base)
        }
        guard generated == errSecSuccess else {
            approvalLog.error("could not generate approval key")
            return nil
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: bytes,
            // ThisDeviceOnly on purpose: the key must not ride iCloud Keychain
            // to other Macs. An approval granted here should not silently
            // authorise the same command on another machine.
            // AfterFirstUnlock rather than WhenUnlocked because Tippi starts at
            // login and expands snippets while the screen may be locked.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            approvalLog.error("Keychain write failed, status=\(status, privacy: .public)")
            return nil
        }
        approvalLog.notice("created snippet approval key")
        return SymmetricKey(data: bytes)
    }
}
