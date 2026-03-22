import Foundation
import Security

/// Thin wrapper around the system Keychain for storing the Anthropic API key.
/// Falls back silently to UserDefaults when running without an entitlement
/// (e.g. SwiftPM Debug builds without code-signing).
enum KeychainService {

    private static let service = "com.yourname.commandbar"
    private static let account = "anthropic-api-key"

    // MARK: - Public API

    static var apiKey: String {
        get { read() ?? UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? "" }
        set {
            let saved = save(newValue)
            if !saved {
                // Keychain unavailable (unsigned Debug build) — fall back
                UserDefaults.standard.set(newValue, forKey: "anthropicAPIKey")
            } else {
                // Remove legacy UserDefaults entry if Keychain succeeded
                UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")
            }
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")
    }

    // MARK: - Private

    private static func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete()

        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String:       data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }
}
