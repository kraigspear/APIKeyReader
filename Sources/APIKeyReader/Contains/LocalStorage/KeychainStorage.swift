import Foundation
import os
import Security

/// Low-level keychain operations for reading, writing, and clearing API key data.
///
/// Keychain operations are intentionally synchronous. Wrapping in `Task.detached` would
/// break actor isolation guarantees in ``APIKeyReader``. Keychain reads/writes complete in <5ms
/// and this library serves low-cardinality key lookups, not high-throughput scenarios.
///
/// - SeeAlso: ``LocalStorage`` which uses this type for persistence.
enum KeychainStorage {
    private static let logger = os.Logger(subsystem: "com.spearware.APIKeyReader", category: "🔑APIKey")
    private static let service = "com.spearware.APIKeyReader"
    typealias KeychainLoad = @Sendable (String) throws -> Data?
    typealias KeychainSave = @Sendable (Data, String) -> Bool
    typealias KeychainClear = @Sendable (String) -> Void
    private struct TestBackend: Sendable {
        let load: KeychainLoad
        let save: KeychainSave
        let clear: KeychainClear
    }

    @TaskLocal
    private static var testBackend: TestBackend?

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                "Keychain read failed with OSStatus: \(status)"
            }
        }
    }

    static func load(account: String) throws -> Data? {
        if let backend = testBackend {
            return try backend.load(account)
        }

        logger.debug("Keychain read operation started for account: \(account, privacy: .private)")
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            logger.debug("Keychain read succeeded for account: \(account, privacy: .private)")
            return result as? Data
        case errSecItemNotFound:
            logger.debug("Keychain read returned not found for account: \(account, privacy: .private)")
            return nil
        default:
            logger.error("Keychain read failed for account: \(account, privacy: .private) with OSStatus: \(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func save(data: Data, account: String) -> Bool {
        if let backend = testBackend {
            return backend.save(data, account)
        }

        logger.debug("Keychain save operation started for account: \(account, privacy: .private)")
        let query = baseQuery(account: account)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            logger.debug("Keychain save updated existing entry for account: \(account, privacy: .private)")
            return true
        case errSecItemNotFound:
            logger
                .debug("Keychain save did not find existing entry for account: \(account, privacy: .private), adding")
            var addQuery = query
            addQuery[kSecValueData as String] = data
            // Formalize access control: device-only, unlocked access. Biometric is intentionally
            // omitted because these are API keys from a public CloudKit database, not user secrets.
            var accessControlError: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [], // cleanup-review: empty flags intentional — keys are from a public CloudKit DB, biometric would be security theater.
                &accessControlError,
            ) else {
                logger.error("Failed to create access control: \(String(describing: accessControlError))")
                return false
            }
            addQuery[kSecAttrAccessControl as String] = accessControl
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("Keychain add failed with OSStatus: \(addStatus)")
                return false
            }
            logger.debug("Keychain add succeeded for account: \(account, privacy: .private)")
            return true
        default:
            logger.error("Keychain update failed with OSStatus: \(updateStatus)")
            return false
        }
    }

    static func clear(account: String) {
        if let backend = testBackend {
            backend.clear(account)
            return
        }

        logger.debug("Keychain clear operation started for account: \(account, privacy: .private)")
        let deleteStatus = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            logger.error("Keychain delete failed with OSStatus: \(deleteStatus)")
            return
        }
        logger.debug("Keychain clear operation completed for account: \(account, privacy: .private)")
    }

    private static func baseQuery(account: String) -> [String: Any] {
        // Keep lookup keys aligned with legacy versions so previously cached entries
        // remain readable after upgrades.
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    #if DEBUG
    static func withTestBackend<R>(
        load: @escaping KeychainLoad,
        save: @escaping KeychainSave,
        clear: @escaping KeychainClear,
        _ operation: () async throws -> R,
    ) async rethrows -> R {
        try await $testBackend.withValue(
            TestBackend(load: load, save: save, clear: clear),
            operation: operation,
        )
    }

    #endif

    /// Selects a valid set of access attributes for SecItemUpdate.
    ///
    /// `kSecAttrAccessControl` and `kSecAttrAccessible` are mutually exclusive in updates.
    /// Prefer access control when available and otherwise preserve accessibility class.
    static func preservedAccessAttributes(from attributes: [String: Any]) -> [String: Any] {
        if let accessControl = attributes[kSecAttrAccessControl as String] {
            return [kSecAttrAccessControl as String: accessControl]
        }
        if let accessible = attributes[kSecAttrAccessible as String] {
            return [kSecAttrAccessible as String: accessible]
        }
        return [:]
    }
}
