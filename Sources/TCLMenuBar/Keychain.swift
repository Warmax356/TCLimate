import Foundation
import Security
import TCLCore

struct SavedLogin: Codable {
    let email: String
    let password: String
    let region: AccountRegion
}

enum LoginKeychain {
    private static let service = "io.loopbreak.TCLimate"
    // Service name used by v0.1.0; migrated on first load.
    private static let legacyService = "local.umar.TCLAir"
    private static let account = "tcl-home-login"
    private static var query: [String: Any] { query(service: service) }
    private static func query(service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() throws -> SavedLogin? {
        if let login = try read(service: service) { return login }
        guard let legacy = try? read(service: legacyService) else { return nil }
        try save(legacy)
        SecItemDelete(query(service: legacyService) as CFDictionary)
        return legacy
    }

    private static func read(service: String) throws -> SavedLogin? {
        var request = query(service: service)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(SavedLogin.self, from: data)
    }

    static func save(_ login: SavedLogin) throws {
        let data = try JSONEncoder().encode(login)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(request as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func delete() throws {
        SecItemDelete(query(service: legacyService) as CFDictionary)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "macOS Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "Could not access saved sign-in.")"
        }
    }
}
