//
//  APIKeyReader.swift
//  Klimate
//
//  Created by Kraig Spear on 10/18/20.
//

import Foundation
import Combine
import os
import SpearFoundation

private struct Log {
    static let logger = os.Logger(subsystem: "com.spearware.foundation", category: "🔑APIKey")
}

/**
 Keys coming from CloudKit
 */
public enum APIKeyName: String, CustomStringConvertible {
    /// Key used with openWeatherMap
    case openWeatherMap = "api.openweathermap.org"
    public var description: String {
        self.rawValue
    }

    /**
     Load the key from Defaults
     - returns: Key if exist or nil
     */
    func load(from defaults: UserDefaultsType) -> String? {
        defaults.string(forKey: self.rawValue)
    }

    /**
     Save value to Defaults
     - parameter defaults: Defaults to save to
     - parameter value: Value to save
     */
    func save(to defaults: UserDefaultsType, value: String?) {
        defaults.set(value, forKey: self.rawValue)
    }
}

public typealias APIKey = String

/**
 Returns an API Key for a given `APIKeyName`
 */
public protocol APIKeyReadable {
    /**
     Loads the key async in a publisher
     - parameter named: Name of the key to retrieve
     - parameter useCachedKey: True to use a previously retrieved cached key. If false the most recent key will be downloaded
     - returns: key for a given `APIKeyName`
     - throws: Error retrieving key

     ```swift
     let apiKey = try await apiKeyReader.apiKey(named: .openWeatherMap)
     let request = coordinate.request(url: .hourly,
     appId: apiKey)
     let json = try await networkSession.loadJSON(from: request)
     ```
     */
    func apiKey(named: APIKeyName, useCachedKey: Bool) async throws -> String

    /**
     Refresh a key from a CloudKit subscription
     https://www.techotopia.com/index.php/An_iOS_8_CloudKit_Subscription_Example
     */
    func refreshKey(userInfo: [AnyHashable: Any]) async throws
}

/**
  ```swift
 let apiKey = try await apiKeyReader.apiKey(named: .openWeatherMap)
 let request = coordinate.request(url: .hourly,
 appId: apiKey)
 let json = try await networkSession.loadJSON(from: request)
 ```
 */
public actor APIKeyReader: APIKeyReadable {

    let log = Log.logger

    private let userDefaults: UserDefaultsType
    private let apiKeyCloudKit: APIKeyCloudKitType

    public init(userDefaults: UserDefaultsType = UserDefaults.standard,
                apiKeyCloudKit: APIKeyCloudKitType = APIKeyCloudKit()) {
        self.userDefaults = userDefaults
        self.apiKeyCloudKit = apiKeyCloudKit
    }

    deinit {
        log.debug("deinit")
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
    public func apiKey(named apiKeyName: APIKeyName,
                       useCachedKey: Bool = true) async throws -> String {

        let log = self.log

        log.debug("Fetching APIKey: \(apiKeyName)")

        // 1. Use existing key from defaults if one exist.
        //    This key may never change. If it does it'll be because
        //    a CloudKit notification, notified us of a changed key which will clear this out.
        // 2. Check if an existing task is running for this key.
        //    If one is running it'll wait for it to complete using the same task
        //    for multiple request.
        // 3. If there isn't a task yet, start one, placing the task in keyFetchState
        //    so that it can be used in Step 2.
        // 4. Start the task to fetch the key from CloudKit

        // 1.
        if useCachedKey {
            if let existingKey = apiKeyName.load(from: userDefaults) {
                log.debug("Key found in defaults for: \(apiKeyName.rawValue)")
                return existingKey
            }
        }

        log.debug("Key not found in defaults for: \(apiKeyName.rawValue)")

        // 2.
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
            case .inProgress(let task):
                log.debug("In progress, awaiting key: \(apiKeyName)")
                // 2a.
                let fetchedAPIKey = try await task.value
                apiKeyName.save(to: userDefaults, value: fetchedAPIKey)

                do {
                    let subscriptionID = try await apiKeyCloudKit.subscribeToCloudKitChanges(apiKeyName: apiKeyName)
                    log.debug("Success subscribing to CloudKit changes")
                    //2b.
                    subscriptionKey = subscriptionID
                } catch {
                    subscriptionKey = nil
                    log.error("Failed to subscribe to cloudKit changes: \(error.localizedDescription)")
                }

                log.debug("Finished, awaiting key: \(fetchedAPIKey)")
                return fetchedAPIKey
            case .finished(let apiKey):
                // 3.
                log.debug("Key is ready, checking freshness key: \(apiKey)")
                return apiKey
            }
        }

        // 3.
        if let key = try await checkExistingKeyTask() {
            return key
        }

        // 4.
        func startFetchTask() async throws -> String {

            // 1. New task created
            // 2. Task is stored in keys, so it's state can be checked when another thread
            //    enters this function
            // 3. Task is executed
            // 4. State is changed to ready when successfully completed
            // 5. Error clears out state for key, so that the fetch can be attempted again

            // 1.
            let fetchTask = Task {
                try await apiKeyCloudKit.fetchAPIKey(apiKeyName)
            }

            // 2.
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
    public func refreshKey(userInfo: [AnyHashable: Any]) async throws {

        log.debug("refreshKey: \(userInfo)")

        let newKey = try await apiKeyCloudKit.fetchNewKey(userInfo: userInfo)
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
                return "inProgress"
            case .finished:
                return "finished"
            }
        }
    }

    /// Stores the fetch state for key fetches
    private var keyFetchState: [APIKeyName: APIKeyFetchState] = [:]

    //MARK: - Defaults

    private var subscriptionKey: String? {
        get { userDefaults.string(forKey: #function) }
        set { userDefaults.set(newValue, forKey: #function) }
    }
}
