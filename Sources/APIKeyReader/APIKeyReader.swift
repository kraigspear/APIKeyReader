//
//  APIKeyReader.swift
//  Klimate
//
//  Created by Kraig Spear on 10/18/20.
//

import Combine
import Foundation
import os

// MARK: - Logging

enum Log {
    static let logger = os.Logger(subsystem: "com.spearware.APIKeyReader", category: "🔑APIKey")
}

private let logger = Log.logger

// MARK: - Errors

enum LoadError: Error {
    case expired(APIKey)
    case decodeError
    case keyDoesNotExist
}

typealias FetchKeyTask = Task<APIKey, Error>

// MARK: - APIKeyReader

/// An actor that manages API keys by fetching them from CloudKit and caching them locally.
///
/// `APIKeyReader` provides a thread-safe way to retrieve API keys with intelligent caching
/// and automatic fallback to expired keys when the network is unavailable.
///
/// ## Overview
///
/// The reader implements several key features:
/// - Concurrent request coalescing to prevent duplicate CloudKit fetches
/// - Local caching with configurable expiration times
/// - Automatic fallback to expired keys during network failures
/// - Thread-safe access through Swift's actor model
///
/// ## Configuration
///
/// Before using the shared instance, you must configure it with your CloudKit container:
///
/// ```swift
/// await APIKeyReader.configure(containerIdentifier: "iCloud.com.example.app")
/// ```
///
/// ## Usage
///
/// ```swift
/// let apiKey = try await APIKeyReader.shared.apiKey(
///     named: .openWeatherMap,
///     expiresMinutes: 60
/// )
/// ```
public actor APIKeyReader {
    // MARK: - Properties
    
    let log = Log.logger
    private let apiKeyCloudKit: CloudKitKeyProvider
    
    /// Stores the fetch state for key fetches to prevent duplicate requests
    private var keyFetchTask: [APIKeyName: Task<APIKey, Error>] = [:]
    
    // MARK: - Shared Instance Management
    
    /// Thread-safe state management for the shared instance
    private actor SharedState {
        private var _instance: APIKeyReader?
        
        func configure(containerIdentifier: String) {
            _instance = .init(
                apiKeyCloudKit: .init(containerIdentifier: containerIdentifier)
            )
        }
        
        var instance: APIKeyReader? {
            _instance
        }
    }
    
    private static let _shared = SharedState()

    /// The shared instance of APIKeyReader.
    ///
    /// - Important: You must call ``configure(containerIdentifier:)`` before accessing this property.
    /// - Note: This property uses async access to ensure thread safety.
    public static var shared: APIKeyReader {
        get async {
            guard let instance = await _shared.instance else {
                Log.logger.fault("Please call configure first")
                fatalError("Please call configure first")
            }
            return instance
        }
    }

    /// Configures the shared APIKeyReader instance with a CloudKit container identifier.
    ///
    /// This method must be called before using the ``shared`` instance, typically during app initialization.
    ///
    /// - Parameter containerIdentifier: The CloudKit container identifier (e.g., "iCloud.com.example.app")
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     init() {
    ///         Task {
    ///             await APIKeyReader.configure(
    ///                 containerIdentifier: "iCloud.com.example.app"
    ///             )
    ///         }
    ///     }
    /// }
    /// ```
    public static func configure(containerIdentifier: String) async {
        await _shared.configure(containerIdentifier: containerIdentifier)
    }

    // MARK: - Initialization
    
    private init(apiKeyCloudKit: CloudKitKeyProvider) {
        self.apiKeyCloudKit = apiKeyCloudKit
    }

    // MARK: - Public Methods
    
    /// Retrieves an API key by name, with caching and automatic CloudKit fetching.
    ///
    /// This method implements intelligent caching behavior:
    /// 1. First checks local cache for a valid (non-expired) key
    /// 2. If expired or not found, fetches from CloudKit
    /// 3. Falls back to expired cached key if network fails
    /// 4. Coalesces concurrent requests for the same key
    ///
    /// - Parameters:
    ///   - apiKeyName: The name of the API key to retrieve
    ///   - expiresMinutes: How long to cache the key locally (in minutes)
    ///
    /// - Returns: The requested API key
    ///
    /// - Throws:
    ///   - `FetchKeyError.networkUnavailable`: Network is not available and no cached key exists
    ///   - `FetchKeyError.recordNotFound`: Key doesn't exist in CloudKit
    ///   - `FetchKeyError.notConfigured`: APIKeyReader hasn't been configured
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     let apiKey = try await APIKeyReader.shared.apiKey(
    ///         named: .openWeatherMap,
    ///         expiresMinutes: 60
    ///     )
    ///     // Use the API key
    /// } catch FetchKeyError.networkUnavailable {
    ///     // Handle offline scenario
    /// }
    /// ```
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

        // MARK: - Local Helper Functions
        
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
}
