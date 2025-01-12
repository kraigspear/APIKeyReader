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

/**
 Keys coming from CloudKit
 */
public enum APIKeyName: String, CustomStringConvertible, Sendable {
    /// Key used with openWeatherMap
    case openWeatherMap = "api.openweathermap.org"
    case rainviewer
    public var description: String {
        rawValue
    }

    /**
     Load the key from Defaults
     - returns: Key if exist or nil
     */
    func load(from defaults: UserDefaults) -> String? {
        guard let data = defaults.data(forKey: rawValue) else {
            logger.debug("\(rawValue) doesn't exist in defaults")
            return nil
        }
        logger.debug("Found \(rawValue) in defaults")
        if let savedAPIKey = try? SavedAPIKey.decode(data) {
            if savedAPIKey.expired {
                logger.debug("APIKey is expired, setting to nil")
                save(to: defaults, value: nil)
            }
            logger.debug("APIKey is fresh, returning")
            return savedAPIKey.key
        }
        logger.error("Wasn't able to decode SavedAPIKey")
        return nil
    }

    /**
     Save value to Defaults
     - parameter defaults: Defaults to save to
     - parameter value: Value to save
     */
    func save(to defaults: UserDefaults, value: String?) {
        guard let value else {
            defaults.set(nil, forKey: rawValue)
            return
        }
        
        if let encodedSavedAPIKey = try? SavedAPIKey(key: value).encode() {
            logger.debug("SavedAPIKey key encoded, saving")
            defaults.set(encodedSavedAPIKey, forKey: rawValue)
        } else {
            logger.error("Can't encode, not saving key")
            assertionFailure("Can't encode")
        }
    }
}

public typealias APIKey = String

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

    private let userDefaults = UserDefaults.standard
    private let apiKeyCloudKit: APIKeyCloudKit

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
    
    public static func configure(apiKeyCloudKit: APIKeyCloudKit) {
        _shared = .init(apiKeyCloudKit: apiKeyCloudKit)
    }

    private init(apiKeyCloudKit: APIKeyCloudKit) {
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
    public func apiKey(named apiKeyName: APIKeyName) async throws -> String {
        let log = log

        log.debug("Fetching APIKey: \(apiKeyName)")

        if let existingKey = apiKeyName.load(from: userDefaults) {
            log.debug("Key found in defaults for: \(apiKeyName.rawValue)")
            return existingKey
        }

        log.debug("Key not found in defaults for: \(apiKeyName.rawValue)")
        
        let task = taskFor(apiKeyName)
        
        do {
            let key = try await task.value
            apiKeyName.save(to: userDefaults, value: key)
            keyFetchState[apiKeyName] = nil
            return key
        } catch {
            keyFetchState[apiKeyName] = nil
            throw error
        }

        func taskFor(_ apiKeyName: APIKeyName) -> Task<String, Error> {
            
            if case let .inProgress(inProgressTask) = keyFetchState[apiKeyName] {
                log.debug("Returning existing task")
                return inProgressTask
            }
            
            log.debug("Starting new task")
            let newTask = Task {
                try await apiKeyCloudKit.fetchAPIKey(apiKeyName)
            }
            
            keyFetchState[apiKeyName] = .inProgress(newTask)
            return newTask
        }
    }

    // MARK: - APIKeyFetchState

    /**
     The state of any task fetching a Key
     */
    private enum APIKeyFetchState: CustomStringConvertible {
        /// The task is currently fetching a key
        case inProgress(Task<APIKey, Error>)
        /// The task has completed for the given key
        case finished(APIKey)

        var description: String {
            switch self {
            case .inProgress:
                "inProgress"
            case .finished:
                "finished"
            }
        }
    }

    /// Stores the fetch state for key fetches
    private var keyFetchState: [APIKeyName: APIKeyFetchState] = [:]
}
