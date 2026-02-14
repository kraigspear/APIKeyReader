import Foundation
import os

// MARK: - APIKeyReader

/// A coordinator for fetching and caching API keys.
///
/// `APIKeyReader` provides a thread-safe way to retrieve API keys with intelligent caching
/// and automatic fallback to expired keys when the network is unavailable.
///
/// `APIKeyReader` conforms to `Observable` so SwiftUI and other Observation-aware
/// views can track cache lifecycle events as part of their normal state observation model.
///
/// ## Overview
///
/// The actor model is required because ``APIKeyReader`` owns mutable concurrent state:
/// the in-flight fetch task map (`keyFetchTask`) and the per-key storage adapter cache.
/// Serializing mutation ensures duplicate suppression, cache consistency, and stable
/// fallback behavior when multiple callers request the same key at once.
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
///
/// - SeeAlso: ``APIKey``
/// - SeeAlso: ``APIKeyName``
/// - SeeAlso: ``FetchKeyError``
public actor APIKeyReader: Observable {
    // MARK: - Properties

    private let keyProvider: any KeyProvider
    private let localStorageFactory: @Sendable (APIKeyName) -> any CachedKeyStorage
    // cleanup-review: unbounded growth is not a concern — cardinality is <10 keys,
    // entries are lightweight structs, and clearCache(for:) removes entries on demand.
    private var storageCache: [APIKeyName: any CachedKeyStorage] = [:]
    /// Stores in-flight fetch tasks keyed by request name to prevent duplicate network calls.
    private var keyFetchTask: [APIKeyName: Task<APIKey, Error>] = [:]

    /// Creates an API key reader backed by CloudKit.
    ///
    /// - Parameter containerIdentifier: The CloudKit container identifier (e.g., `"iCloud.com.example.app"`).
    ///   Must match a container configured in your app's CloudKit capabilities.
    public init(containerIdentifier: String) {
        keyProvider = CloudKitKeyProvider(containerIdentifier: containerIdentifier)
        localStorageFactory = { LocalStorage(key: $0) }
    }

    /// Internal initializer for dependency injection in tests and custom deployments.
    ///
    /// This allows callers to provide alternate ``KeyProvider`` and storage factories
    /// while keeping the actor’s concurrency and cache behavior intact.
    init(
        keyProvider: any KeyProvider,
        localStorageFactory: @escaping @Sendable (APIKeyName) -> any CachedKeyStorage = { LocalStorage(key: $0) },
    ) {
        self.keyProvider = keyProvider
        self.localStorageFactory = localStorageFactory
    }

    // MARK: - Public API

    /// Removes the cached key from the Keychain.
    ///
    /// Call this after logout, account switching, or when rotating a key to force the
    /// next request to re-fetch from CloudKit.
    ///
    /// - Parameter apiKeyName: The name of the API key to clear.
    public func clearCache(for apiKeyName: APIKeyName) async {
        if let storage = storageCache.removeValue(forKey: apiKeyName) {
            await storage.clear()
        } else {
            await localStorageFactory(apiKeyName).clear()
        }
    }

    /// Retrieves a key by name using cache-first behavior.
    ///
    /// This method implements intelligent caching behavior:
    /// 1. First checks local cache for a valid (non-expired) key
    /// 2. If expired or not found, fetches from CloudKit
    /// 3. Falls back to expired cached key if network fails
    /// 4. Coalesces concurrent requests for the same key
    ///
    /// - Parameters:
    ///   - apiKeyName: The name of the API key to retrieve
    ///   - expiresMinutes: How long to cache the key locally (in minutes). Recommended values
    ///     are typically **60 to 1440** depending on how frequently keys are rotated.
    ///
    /// - Returns: The requested API key
    ///
    /// - Throws: ``FetchKeyError`` with one of the following cases:
    ///   - ``FetchKeyError/networkUnavailable``: Network is unavailable and no cached key exists.
    ///   - ``FetchKeyError/recordNotFound``: Key doesn't exist in CloudKit.
    ///   - ``FetchKeyError/cloudKitRestricted``: iCloud access is restricted on this device.
    ///   - ``FetchKeyError/missingField(named:)``: CloudKit record schema is missing an expected field.
    ///   - ``FetchKeyError/cloudKitError(error:)``: Other CloudKit operation failures.
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
        #if DEBUG
        logger.debug("Fetching APIKey: \(apiKeyName, privacy: .private)")
        #endif

        let localStorage = storage(for: apiKeyName)
        let storageResult = try await cachedValue(for: localStorage, apiKeyName: apiKeyName)

        let expiredKey: APIKey?
        switch storageResult {
        case let .value(apiKey):
            return apiKey
        case let .expired(apiKey):
            logger.debug("key is expired")
            expiredKey = apiKey
        case .missing:
            expiredKey = nil
        }

        #if DEBUG
        logger.debug("Key not found or expired in keychain for: \(apiKeyName, privacy: .private)")
        #endif

        return try await fetchKey(
            task: taskFor(apiKeyName),
            apiKeyName: apiKeyName,
            localStorage: localStorage,
            expiresMinutes: expiresMinutes,
            expiredKey: expiredKey,
        )
    }

    // MARK: - Cache Lookup

    private func cachedValue(
        for localStorage: any CachedKeyStorage,
        apiKeyName: APIKeyName,
    ) async throws -> CacheLookupResult {
        do {
            return try await .value(localStorage.load())
        } catch let loadError as LoadError {
            switch loadError {
            case .decodeError:
                await localStorage.clear()
                return .missing
            case let .expired(key):
                return .expired(key)
            case .keyDoesNotExist:
                return .missing
            case let .keychainError(error):
                // cleanup-review: .public is correct — error type names and OSStatus codes don't contain
                // secrets and are needed for production diagnostics (see Doc/LoggingPrivacy.md).
                logger.error(
                    "Local storage read failed for \(apiKeyName, privacy: .private); falling back to provider: \(String(describing: error), privacy: .public)",
                )
                return .missing
            }
        } catch {
            // cleanup-review: .public is correct — same rationale as above.
            logger.error("Unexpected local storage error: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    // MARK: - Task Management

    private func taskFor(_ apiKeyName: APIKeyName) -> Task<APIKey, Error> {
        if let inProgressTask = keyFetchTask[apiKeyName] {
            logger.debug("Returning existing task")
            return inProgressTask
        }

        logger.debug("Starting new task")
        let newTask = Task {
            try await keyProvider.fetchAPIKey(apiKeyName)
        }

        keyFetchTask[apiKeyName] = newTask
        return newTask
    }

    // MARK: - Key Fetching

    private func fetchKey(
        task: Task<APIKey, Error>,
        apiKeyName: APIKeyName,
        localStorage: any CachedKeyStorage,
        expiresMinutes: Int,
        expiredKey: APIKey?,
    ) async throws -> APIKey {
        defer { keyFetchTask.removeValue(forKey: apiKeyName) }

        do {
            let freshKey = try await task.value
            await localStorage.save(
                value: freshKey,
                expiresMinutes: expiresMinutes,
            )
            return freshKey
        } catch let error as CancellationError {
            throw error
        } catch FetchKeyError.cloudKitRestricted {
            logger.error("CloudKit is restricted for key: \(apiKeyName, privacy: .private)")
            throw FetchKeyError.cloudKitRestricted
        } catch {
            logger.error("Error fetching new key: \(error)")

            // If we have a previous key, and we can't get a new one
            // we'll attempt to use it.
            if let expiredKey {
                return expiredKey
            }

            throw error
        }
    }

    private func storage(for apiKeyName: APIKeyName) -> any CachedKeyStorage {
        if let existing = storageCache[apiKeyName] {
            return existing
        }
        let newStorage = localStorageFactory(apiKeyName)
        storageCache[apiKeyName] = newStorage
        return newStorage
    }
}

// MARK: - Supporting Types

private let logger = os.Logger(subsystem: "com.spearware.APIKeyReader", category: "🔑APIKey")

private enum CacheLookupResult {
    case value(APIKey)
    case expired(APIKey)
    case missing
}
