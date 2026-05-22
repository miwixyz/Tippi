import Foundation
import Security

enum KeychainError: LocalizedError {
    case unhandledError(status: OSStatus)
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .unhandledError(let status):
            return "Keychain error (\(status))"
        case .unexpectedData:
            return "Keychain returned unexpected data"
        }
    }
}

/// Stores BYOK API keys for each LLM provider in the macOS Keychain.
/// Items are scoped to `com.tippi.app` and the account `provider.<name>`,
/// accessible only while the device is unlocked and **not** synced via iCloud.
enum KeychainStore {
    static let service = "com.tippi.app"

    static func setAPIKey(_ key: String, for provider: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteAPIKey(for: provider)
            return
        }

        let account = "provider.\(provider)"
        let data = Data(trimmed.utf8)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: addStatus)
            }
        default:
            throw KeychainError.unhandledError(status: updateStatus)
        }
    }

    static func getAPIKey(for provider: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "provider.\(provider)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return key
    }

    static func deleteAPIKey(for provider: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "provider.\(provider)"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    static func hasAPIKey(for provider: String) -> Bool {
        (try? getAPIKey(for: provider)) != nil
    }
}
