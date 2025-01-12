//
//  LocalStorage.swift
//  APIKeyReader
//
//  Created by Kraig Spear on 1/12/25.
//

import Foundation

private let logger = Log.logger

struct LocalStorage {
    private let key: APIKeyName
    private let defaults = UserDefaults.standard

    init(key: APIKeyName) {
        self.key = key
    }

    func load() throws -> APIKey {
        guard let data = UserDefaults.standard.data(forKey: key.rawValue) else {
            logger.debug("\(key) doesn't exist in defaults")
            throw LoadError.keyDoesNotExist
        }
        logger.debug("Found \(key) in defaults")
        if let savedAPIKey = try? SavedAPIKey.decode(data) {
            if savedAPIKey.expired {
                throw LoadError.expired(savedAPIKey.key)
            }
            logger.debug("APIKey is fresh, returning")
            return savedAPIKey.key
        }
        logger.error("Wasn't able to decode SavedAPIKey")
        throw LoadError.decodeError
    }

    func clear() {
        defaults.set(nil, forKey: key.rawValue)
    }

    func save(value: APIKey?, expiresMinutes: Int) {
        guard let value else {
            defaults.set(nil, forKey: key.rawValue)
            return
        }

        if let encodedSavedAPIKey = try? SavedAPIKey(
            key: value,
            expiresMinutes: expiresMinutes
        ).encode() {
            logger.debug("SavedAPIKey key encoded, saving")
            defaults.set(encodedSavedAPIKey, forKey: key.rawValue)
        } else {
            logger.error("Can't encode, not saving key")
            assertionFailure("Can't encode")
        }
    }
}
