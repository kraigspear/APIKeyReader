import Foundation
import Security

private let logger = Log.logger

struct LocalStorage: CachedKeyStorage {
    private let key: APIKeyName

    init(key: APIKeyName) {
        self.key = key
    }

    func load() throws -> APIKey {
        guard let data = KeychainStorage.load(account: key.rawValue) else {
            logger.debug("\(key) doesn't exist in keychain")
            throw LoadError.keyDoesNotExist
        }
        logger.debug("Found \(key) in keychain")

        let savedAPIKey: SavedAPIKey
        do {
            savedAPIKey = try SavedAPIKey.decode(data)
        } catch {
            logger.error("Wasn't able to decode SavedAPIKey: \(error)")
            throw LoadError.decodeError
        }

        if savedAPIKey.expired {
            throw LoadError.expired(savedAPIKey.key)
        }

        logger.debug("APIKey is fresh, returning")
        return savedAPIKey.key
    }

    func clear() {
        KeychainStorage.clear(account: key.rawValue)
    }

    func save(value: APIKey?, expiresMinutes: Int) {
        guard let value else {
            KeychainStorage.clear(account: key.rawValue)
            return
        }

        guard let encodedSavedAPIKey = try? SavedAPIKey(
            key: value,
            expiresMinutes: expiresMinutes,
        ).encode() else {
            logger.error("Can't encode, not saving key")
            return
        }

        logger.debug("SavedAPIKey key encoded, saving")
        if KeychainStorage.save(data: encodedSavedAPIKey, account: key.rawValue) {
            logger.debug("Saved \(key) to keychain")
        } else {
            logger.error("Failed to save \(key) to keychain")
        }
    }
}

private enum KeychainStorage {
    private static let service = "com.spearware.APIKeyReader"

    static func load(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            logger.error("Keychain read failed with OSStatus: \(status)")
            return nil
        }
    }

    static func save(data: Data, account: String) -> Bool {
        let query = baseQuery(account: account)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("Keychain add failed with OSStatus: \(addStatus)")
                return false
            }
            return true
        default:
            logger.error("Keychain update failed with OSStatus: \(updateStatus)")
            return false
        }
    }

    static func clear(account: String) {
        let deleteStatus = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            logger.error("Keychain delete failed with OSStatus: \(deleteStatus)")
            return
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
