//
//  APIKeyReader.swift
//  Klimate
//
//  Created by Kraig Spear on 10/18/20.
//

import Combine
import Foundation
import os

enum Log {
    static let logger = os.Logger(subsystem: "com.spearware.APIKeyReader", category: "🔑APIKey")
}

private let logger = Log.logger

public struct APIKeyName: RawRepresentable, Hashable, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String {
        rawValue
    }
}

enum LoadError: Error {
    case expired(APIKey)
    case decodeError
    case keyDoesNotExist
}

typealias FetchKeyTask = Task<APIKey, Error>

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

public struct APIKey: RawRepresentable, CustomStringConvertible, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    public var description: String {
        rawValue
    }
}

/**
  ```swift
 let apiKey = try await apiKeyReader.apiKey(named: .openWeatherMap)
 let request = coordinate.request(url: .hourly,
 appId: apiKey)
 let json = try await networkSession.loadJSON(from: request)
 ```
 */
public actor APIKeyReader {
    let log = Log.logger

    private let apiKeyCloudKit: CloudKitKeyProvider

    /// Default shared instance.
    /// Having one instance can help if the key is being refreshed and accessed close to the same time
    private static var _shared: APIKeyReader?
    
    public static var shared: APIKeyReader {
        guard let _shared else {
            Log.logger.fault("Please call configure first")
            fatalError("Please call configure first")
        }
        return _shared
    }
    
    public static func configure(containerIdentifier: String) {
        _shared = .init(
            apiKeyCloudKit: .init(containerIdentifier: containerIdentifier)
        )
    }

    private init(apiKeyCloudKit: CloudKitKeyProvider) {
        self.apiKeyCloudKit = apiKeyCloudKit
    }

    /**
     Loads the key async in a publisher
     - parameter named: Name of the key to retrieve
     - returns: key for a given `APIKeyName`
     - throws: FetchKeyError.cloudKitError

     ```swift
     let apiKey = try await apiKeyReader.apiKey(named: .openWeatherMap)
     let request = coordinate.request(url: .hourly,
     appId: apiKey)
     let json = try await networkSession.loadJSON(from: request)
     ```
     */
    public func apiKey(
        named apiKeyName: APIKeyName,
        expiresMinutes: Int
    ) async throws -> APIKey {
        let log = log

        log.debug("Fetching APIKey: \(apiKeyName)")
        
        // We can fallback to this if we have errors loading from CloudKit
        let expiredKey: APIKey?
        
        let localStorage = LocalStorage(key: apiKeyName)
        
        do {
            return try localStorage.load()
        } catch LoadError.decodeError {
            expiredKey = nil
            localStorage.clear()
        } catch let LoadError.expired(key) {
            logger.debug("key is expired")
            expiredKey = key
        } catch LoadError.keyDoesNotExist {
            expiredKey = nil
        } catch {
            expiredKey = nil
            assertionFailure("Unknown error")
            logger.error("Unhandled error")
        }
        
        log.debug("Key not found or expired in defaults for: \(apiKeyName)")
        
        let key = try await fetchKey(task: taskFor(apiKeyName))
        
        localStorage.save(
            value: key,
            expiresMinutes: expiresMinutes
        )
        
        keyFetchTask[apiKeyName] = nil
        return key

        func taskFor(_ apiKeyName: APIKeyName) -> FetchKeyTask {
            
            if let inProgressTask = keyFetchTask[apiKeyName] {
                log.debug("Returning existing task")
                return inProgressTask
            }
            
            log.debug("Starting new task")
            let newTask = Task {
                try await apiKeyCloudKit.fetchAPIKey(apiKeyName)
            }
            
            keyFetchTask[apiKeyName] = newTask
            return newTask
        }
        
        func fetchKey(task: Task<APIKey, Error>) async throws -> APIKey {
            do {
                return try await task.value
            } catch {
                keyFetchTask[apiKeyName] = nil
                
                log.error("Error fetching new key: \(error)")
                
                // If we have a previous key, and we can't get a new one
                // we'll attempt to use it.
                if let expiredKey {
                    return expiredKey
                }
                
                throw error
            }
        }
    }

    /// Stores the fetch state for key fetches
    private var keyFetchTask: [APIKeyName: Task<APIKey, Error>] = [:]
}
