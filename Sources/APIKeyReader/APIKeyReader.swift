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

// MARK: - KeyProvider

protocol KeyProvider: Sendable {
    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey
}

extension CloudKitKeyProvider: KeyProvider {}

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
/// ## Initialization
///
/// Create an instance with your CloudKit container identifier:
///
/// ```swift
/// let apiKeyReader = APIKeyReader(containerIdentifier: "iCloud.com.example.app")
/// ```
///
/// ## Usage
///
/// ```swift
/// let apiKey = try await apiKeyReader.apiKey(
///     named: .openWeatherMap,
///     expiresMinutes: 60
/// )
/// ```
public actor APIKeyReader: Observable {
    // MARK: - Properties

    let log = Log.logger
    private let keyProvider: any KeyProvider

    public init(containerIdentifier: String) {
        keyProvider = CloudKitKeyProvider(containerIdentifier: containerIdentifier)
    }

    init(keyProvider: any KeyProvider) {
        self.keyProvider = keyProvider
    }

    /// Stores the fetch state for key fetches to prevent duplicate requests
    private var keyFetchTask: [APIKeyName: Task<APIKey, Error>] = [:]

    // MARK: - Public Methods

    /// Removes the cached key from the Keychain.
    ///
    /// - Parameter apiKeyName: The name of the API key to clear
    public func clearCache(for apiKeyName: APIKeyName) {
        LocalStorage(key: apiKeyName).clear()
    }

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
    ///   - Other CloudKit-related errors
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     let apiKey = try await apiKeyReader.apiKey(
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
        expiresMinutes: Int,
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
                try await keyProvider.fetchAPIKey(apiKeyName)
            }

            keyFetchTask[apiKeyName] = newTask
            return newTask
        }

        func fetchKey(task: Task<APIKey, Error>) async throws -> APIKey {
            do {
                let freshKey = try await task.value
                localStorage.save(
                    value: freshKey,
                    expiresMinutes: expiresMinutes,
                )
                return freshKey
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
