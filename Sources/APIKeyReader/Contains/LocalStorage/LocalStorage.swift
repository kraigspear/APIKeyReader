import Foundation
import os

/// Internal `CachedKeyStorage` implementation backed by the Apple Keychain.
///
/// This adapter is intentionally internal to the package and keeps keychain behavior
/// isolated behind the storage protocol used by ``APIKeyReader``.
///
/// - SeeAlso: ``CachedKeyStorage`` for the protocol this type conforms to.
/// - SeeAlso: ``KeychainStorage`` for the low-level keychain operations.
/// - SeeAlso: ``SavedAPIKey`` for the encoded keychain entry format.
struct LocalStorage: CachedKeyStorage {
    // MARK: - Properties

    private static let logger = os.Logger(subsystem: "com.spearware.APIKeyReader", category: "🔑APIKey")

    private let key: APIKeyName

    init(key: APIKeyName) {
        self.key = key
    }

    // MARK: - CachedKeyStorage

    func load() async throws -> APIKey {
        Self.logger.debug("Loading API key from keychain for account: \(key.rawValue, privacy: .private)")
        let data: Data?
        do {
            data = try KeychainStorage.load(account: key.rawValue)
        } catch {
            Self.logger
                .error(
                    "Read failed while loading from keychain for account \(key.rawValue, privacy: .private): \(error)",
                )
            throw LoadError.keychainError(error)
        }
        guard let data else {
            Self.logger.debug("No keychain entry for account: \(key.rawValue, privacy: .private)")
            throw LoadError.keyDoesNotExist
        }
        Self.logger.debug("Found \(key, privacy: .private) in keychain")

        let savedAPIKey: SavedAPIKey
        do {
            savedAPIKey = try SavedAPIKey.decode(data)
        } catch {
            Self.logger.error("Wasn't able to decode SavedAPIKey: \(error)")
            throw LoadError.decodeError
        }

        if savedAPIKey.expired {
            throw LoadError.expired(savedAPIKey.key)
        }

        Self.logger.debug("APIKey is fresh, returning")
        return savedAPIKey.key
    }

    func clear() async {
        Self.logger.debug("Clearing keychain entry for account: \(key.rawValue, privacy: .private)")
        KeychainStorage.clear(account: key.rawValue)
    }

    func save(value: APIKey?, expiresMinutes: Int) async {
        guard let value else {
            Self.logger
                .debug(
                    "Clearing keychain entry for account: \(key.rawValue, privacy: .private) because save value was nil",
                )
            KeychainStorage.clear(account: key.rawValue)
            return
        }

        Self.logger
            .debug(
                "Saving API key for account: \(key.rawValue, privacy: .private) with expiry minutes: \(expiresMinutes)",
            )

        let encodedSavedAPIKey: Data
        do {
            encodedSavedAPIKey = try SavedAPIKey(
                key: value,
                expiresMinutes: expiresMinutes,
            ).encode()
        } catch {
            Self.logger.error("Failed to encode SavedAPIKey: \(error)")
            return
        }

        Self.logger.debug("SavedAPIKey key encoded, saving")
        if KeychainStorage.save(data: encodedSavedAPIKey, account: key.rawValue) {
            Self.logger.debug("Saved \(key, privacy: .private) to keychain")
        } else {
            Self.logger.error("Failed to save \(key, privacy: .private) to keychain")
        }
    }
}
