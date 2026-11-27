import Foundation
import Security

/// Lightweight macOS Keychain wrapper for securely storing API keys instead of plaintext JSON.
public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore()

    private let service: String
    private let legacyService: String?

    public init(service: String = "com.sonote.app", legacyService: String? = "com.ttminutes.app") {
        self.service = service
        self.legacyService = (legacyService == service) ? nil : legacyService
    }

    @discardableResult
    public func save(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return delete(account: account)
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        var addItem = query
        addItem[kSecValueData as String] = data
        addItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addItem as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    public func read(account: String) -> String? {
        if let value = readRaw(service: service, account: account) {
            return value
        }
        // Seamless one-time migration from legacy `com.ttminutes.app` Keychain items
        if let legacyService, let migrated = readRaw(service: legacyService, account: account) {
            _ = save(migrated, account: account)
            return migrated
        }
        return nil
    }

    private func readRaw(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    @discardableResult
    public func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
