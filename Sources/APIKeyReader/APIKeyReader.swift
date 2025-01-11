//
//  APIKeyReader.swift
//  Klimate
//
//  Created by Kraig Spear on 10/18/20.
//

import Combine
import Foundation
import os

private enum Log {
    static let logger = os.Logger(subsystem: "com.spearware.foundation", category: "🔑APIKey")
}

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
        defaults.string(forKey: rawValue)
    }

    /**
     Save value to Defaults
     - parameter defaults: Defaults to save to
     - parameter value: Value to save
     */
    func save(to defaults: UserDefaults, value: String?) {
        defaults.set(value, forKey: rawValue)
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
    
    public static func configure(apiKeyCloudKit: APIKeyCloudKit) -> APIKeyReader {
        if let _shared { return _shared }
        _shared = .init(apiKeyCloudKit: apiKeyCloudKit)
        return _shared!
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

        if let key = try await checkExistingKeyTask() {
            return key
        }

        func checkExistingKeyTask() async throws -> String? {
            // 1. If there is an existing key, meaning has a task been started to fetch this key
            //   CloudKit yet?
            //
            // 2. Check if this task is in progress, or has finished.
            // 2a. If the task is in progress, wait for it to complete
            // 2b. Save the key to defaults, so that it can be uses later, avoid fetching again
            //
            // 3.  If the key has been fetched already, return the key

            guard let existingKey = keyFetchState[apiKeyName] else { return nil }
            log.debug("Existing key: \(apiKeyName)")

            // 2.
            switch existingKey {
            case let .inProgress(task):
                log.debug("In progress, awaiting key: \(apiKeyName)")
                // 2a.
                let fetchedAPIKey = try await task.value
                apiKeyName.save(to: userDefaults, value: fetchedAPIKey)

                do {
                    let subscriptionID = try await apiKeyCloudKit.subscribeToCloudKitChanges(apiKeyName: apiKeyName)
                    log.debug("Success subscribing to CloudKit changes")
                    // 2b.
                    subscriptionKey = subscriptionID
                } catch {
                    subscriptionKey = nil
                    log.error("Failed to subscribe to cloudKit changes: \(error.localizedDescription)")
                }

                log.debug("Finished, awaiting key: \(fetchedAPIKey)")
                return fetchedAPIKey
            case let .finished(apiKey):
                // 3.
                log.debug("Key is ready, checking freshness key: \(apiKey)")
                apiKeyName.save(to: userDefaults, value: apiKey)
                return apiKey
            }
        }
        
        func startFetchTask() async throws -> String {
            let fetchTask = Task {
                try await apiKeyCloudKit.fetchAPIKey(apiKeyName)
            }

            keyFetchState[apiKeyName] = .inProgress(fetchTask)
            log.debug("keys: \(apiKeyName.rawValue) to: inProgress")

            do {
                log.debug("Awaiting fetch task in DO block: \(apiKeyName)")
                // 3.
                let apiKeyValue = try await fetchTask.value
                log.debug("Finished fetch task: \(apiKeyName)")
                log.debug("keys: \(apiKeyName.rawValue) to: ready")
                // 4.
                keyFetchState[apiKeyName] = .finished(apiKeyValue)
                log.debug("Returning key: \(apiKeyName) in DO block")
                return apiKeyValue
            } catch {
                log.error("Error for key: \(apiKeyName) error: \(error.localizedDescription)")
                // 5.
                keyFetchState[apiKeyName] = nil
                throw error
            }
        }

        return try await startFetchTask()
    }

    /**
     Called from App 'appDelegate.didReceiveRemoteNotification'
     To handle a silent push, needing to refresh an API key from CloudKit

     - parameter userInfo: Dictionary with information about the push notification. Passed directly from didReceiveRemoteNotification
     */
    public func refreshKey(_ keyRefreshInfo: KeyRefreshInfo) async throws {
        log.debug("refreshKey with recordID: \(keyRefreshInfo.recordID)")

        let newKey = try await apiKeyCloudKit.fetchNewKey(for: keyRefreshInfo.recordID)
        log.debug("NewKey retrieved from CloudKit named: \(newKey.name)")

        guard let apiKeyName = APIKeyName(rawValue: newKey.name) else {
            assertionFailure("Retrieved a key from CouldKit not found in APIKeyName")
            return
        }

        apiKeyName.save(to: userDefaults, value: newKey.key)
        log.info("NewKey saved: \(newKey.name)")
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

    // MARK: - Defaults

    private var subscriptionKey: String? {
        get { userDefaults.string(forKey: #function) }
        set { userDefaults.set(newValue, forKey: #function) }
    }
}
