import Foundation
import Testing
@testable import APIKeyReader

// MARK: - APIKeyReader Tests

@Suite("APIKeyReader")
struct APIKeyReaderTests {
    private func reader(
        provider: any KeyProvider,
        state: TestStorageState,
    ) -> APIKeyReader {
        APIKeyReader(
            keyProvider: provider,
            localStorageFactory: { _ in
                TestCachedKeyStorage(state: state) as any CachedKeyStorage
            },
        )
    }

    @Test("returns valid cached key without calling provider")
    func returnsValidCachedKey() async throws {
        // Given: cache has a fresh, valid key.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let cachedKey = APIKey(rawValue: "cached-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .value(cachedKey))

        let provider = FailingKeyProvider(error: FetchKeyError.networkUnavailable)
        let reader = reader(provider: provider, state: storageState)

        // When: requesting the key.
        let result = try await reader.apiKey(named: keyName, expiresMinutes: 60)

        // Then: the cached key is returned and provider was never called (no save).
        #expect(result.rawValue == cachedKey.rawValue)
        #expect(await storageState.saveCallCount == 0)
    }

    @Test("fetches from provider when cache is empty")
    func fetchesWhenCacheEmpty() async throws {
        // Given: no cached key exists and provider returns a fresh key.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expectedKey = APIKey(rawValue: "fresh-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keyDoesNotExist))

        let provider = SucceedingKeyProvider(apiKey: expectedKey)
        let reader = reader(provider: provider, state: storageState)

        // When: requesting the key through APIKeyReader.
        let result = try await reader.apiKey(named: keyName, expiresMinutes: 60)

        // Then: the fetched provider key is returned.
        #expect(result.rawValue == expectedKey.rawValue)
        #expect(await storageState.saveCallCount == 1)
        #expect(await (storageState.lastSavedKey)?.rawValue == expectedKey.rawValue)
    }

    @Test("does not crash for non-positive expiry values")
    func doesNotCrashForNonPositiveExpiryValues() async throws {
        // Given: no cached key and a provider that can always return a key.
        let firstKeyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let secondKeyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expectedKey = APIKey(rawValue: "fresh-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keyDoesNotExist))
        let provider = SucceedingKeyProvider(apiKey: expectedKey)
        let reader = reader(provider: provider, state: storageState)

        // When: requesting keys with zero and negative expiry values.
        let zeroExpiryResult = try await reader.apiKey(named: firstKeyName, expiresMinutes: 0)
        let negativeExpiryResult = try await reader.apiKey(named: secondKeyName, expiresMinutes: -1)

        // Then: requests still succeed and return provider values.
        #expect(zeroExpiryResult.rawValue == expectedKey.rawValue)
        #expect(negativeExpiryResult.rawValue == expectedKey.rawValue)
        #expect(await storageState.saveCallCount == 2)
    }

    @Test("fetches from provider when local keychain read fails")
    func fetchesWhenLocalKeychainReadFails() async throws {
        // Given: local storage reports a keychain read failure.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expectedKey = APIKey(rawValue: "fresh-\(UUID().uuidString)")
        let keychainFailure = NSError(domain: "NSOSStatusErrorDomain", code: -25308)
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keychainError(keychainFailure)))

        let provider = SucceedingKeyProvider(apiKey: expectedKey)
        let reader = reader(provider: provider, state: storageState)

        // When: requesting the key through APIKeyReader.
        let result = try await reader.apiKey(named: keyName, expiresMinutes: 60)

        // Then: APIKeyReader falls back to provider and still returns/saves fresh key.
        #expect(result.rawValue == expectedKey.rawValue)
        #expect(await storageState.saveCallCount == 1)
        #expect(await (storageState.lastSavedKey)?.rawValue == expectedKey.rawValue)
    }

    @Test("continues when storage save cannot persist value")
    func continuesWhenStorageSaveFails() async throws {
        // Given: provider returns a key and storage cannot persist it.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expectedKey = APIKey(rawValue: "fresh-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keyDoesNotExist))
        let storage = SaveFailureStorage(state: storageState)

        let provider = SucceedingKeyProvider(apiKey: expectedKey)
        let reader = APIKeyReader(
            keyProvider: provider,
            localStorageFactory: { _ in
                storage as any CachedKeyStorage
            },
        )

        // When: requesting the key.
        let result = try await reader.apiKey(named: keyName, expiresMinutes: 60)

        // Then: fetch succeeds even if save cannot persist.
        #expect(result.rawValue == expectedKey.rawValue)
        #expect(await storage.didAttemptSave)
    }

    @Test("coalesces concurrent fetches for same key")
    func coalescesConcurrentFetchesForSameKey() async throws {
        // Given: a delayed provider and two concurrent reads for the same key.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expectedKey = APIKey(rawValue: "coalesced-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keyDoesNotExist))

        let provider = CountingDelayedKeyProvider(
            apiKey: expectedKey,
            delay: .milliseconds(100),
        )
        let reader = reader(provider: provider, state: storageState)

        // When: both requests are started before the first one completes.
        async let first = reader.apiKey(named: keyName, expiresMinutes: 60)
        async let second = reader.apiKey(named: keyName, expiresMinutes: 60)
        let (firstKey, secondKey) = try await (first, second)

        // Then: both calls return the same value and only one provider fetch occurs.
        #expect(firstKey.rawValue == expectedKey.rawValue)
        #expect(secondKey.rawValue == expectedKey.rawValue)
        #expect(await provider.fetchCount == 1)
    }

    @Test("coalesces concurrent fetches per key only")
    func coalescesConcurrentFetchesForDifferentKeys() async throws {
        // Given: a delayed provider that returns unique keys for each request name.
        let firstKey = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let secondKey = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let firstValue = APIKey(rawValue: "first-\(UUID().uuidString)")
        let secondValue = APIKey(rawValue: "second-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keyDoesNotExist))

        let provider = MappingKeyProvider(
            mapping: [
                firstKey: firstValue,
                secondKey: secondValue,
            ],
            fallback: APIKey(rawValue: "fallback"),
            delay: .milliseconds(100),
        )
        let reader = reader(provider: provider, state: storageState)

        // When: both reads run concurrently but for different keys.
        async let first = reader.apiKey(named: firstKey, expiresMinutes: 60)
        async let second = reader.apiKey(named: secondKey, expiresMinutes: 60)
        let (firstResult, secondResult) = try await (first, second)

        // Then: both requests complete independently and each key path is fetched once.
        #expect(firstResult.rawValue == firstValue.rawValue)
        #expect(secondResult.rawValue == secondValue.rawValue)
        #expect(await provider.fetchCount == 2)
    }

    @Test("throws when provider fails and no cached key exists")
    func throwsWhenNoFallback() async {
        // Given: provider fails and no cached key exists.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keyDoesNotExist))

        let provider = FailingKeyProvider(error: FetchKeyError.networkUnavailable)
        let reader = reader(provider: provider, state: storageState)

        // When/Then: requesting the key surfaces networkUnavailable.
        await #expect {
            try await reader.apiKey(named: keyName, expiresMinutes: 60)
        } throws: { error in
            guard let fetchError = error as? FetchKeyError else { return false }
            if case .networkUnavailable = fetchError { return true }
            return false
        }
    }

    @Test("returns expired cached key when provider fails")
    func returnsExpiredCachedKeyWhenProviderFails() async throws {
        // Given: cache load reports an expired key and provider fails.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expiredKey = APIKey(rawValue: "expired-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.expired(expiredKey)))

        let provider = FailingKeyProvider(error: FetchKeyError.networkUnavailable)
        let reader = reader(provider: provider, state: storageState)

        // When: requesting the key and CloudKit fetch fails.
        let result = try await reader.apiKey(named: keyName, expiresMinutes: 60)

        // Then: APIKeyReader falls back to the expired cached key.
        #expect(result.rawValue == expiredKey.rawValue)
    }

    @Test("rethrows cancellation when provider is canceled")
    func rethrowsCancellationWhenProviderIsCanceled() async {
        // Given: cache has an expired key but provider is canceled.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expiredKey = APIKey(rawValue: "expired-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.expired(expiredKey)))

        let provider = FailingKeyProvider(error: CancellationError())
        let reader = reader(provider: provider, state: storageState)

        // When/Then: cancellation propagates instead of falling back.
        await #expect {
            try await reader.apiKey(named: keyName, expiresMinutes: 60)
        } throws: { error in
            error is CancellationError
        }
    }

    @Test("clears corrupt cached key when decode fails")
    func clearsCorruptCachedKeyWhenDecodeFails() async {
        // Given: cache load reports decode failure and provider fails.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.decodeError))

        let provider = FailingKeyProvider(error: FetchKeyError.networkUnavailable)
        let reader = reader(provider: provider, state: storageState)

        // When: requesting the key triggers decode failure and cache clear.
        await #expect {
            try await reader.apiKey(named: keyName, expiresMinutes: 60)
        } throws: { error in
            guard let fetchError = error as? FetchKeyError else { return false }
            if case .networkUnavailable = fetchError { return true }
            return false
        }

        // Then: malformed cached value has been removed from local storage.
        #expect(await storageState.clearCallCount == 1)
    }

    @Test("rethrows unexpected storage errors")
    func rethrowsUnexpectedStorageErrors() async {
        // Given: cache load throws a non-LoadError and provider would succeed.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let unexpectedError = NSError(domain: "test", code: 42)
        let storageState = TestStorageState(loadBehavior: .error(unexpectedError))

        let provider = SucceedingKeyProvider(apiKey: APIKey(rawValue: "unused"))
        let reader = reader(provider: provider, state: storageState)

        // When/Then: the unexpected error propagates without being swallowed.
        await #expect {
            try await reader.apiKey(named: keyName, expiresMinutes: 60)
        } throws: { error in
            (error as NSError).domain == "test" && (error as NSError).code == 42
        }
    }

    @Test("throws cloudKitRestricted when provider reports restricted access")
    func throwsCloudKitRestricted() async {
        // Given: provider throws cloudKitRestricted and no cached key exists.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keyDoesNotExist))

        let provider = FailingKeyProvider(error: FetchKeyError.cloudKitRestricted)
        let reader = reader(provider: provider, state: storageState)

        // When/Then: the restricted error propagates.
        await #expect {
            try await reader.apiKey(named: keyName, expiresMinutes: 60)
        } throws: { error in
            guard let fetchError = error as? FetchKeyError else { return false }
            if case .cloudKitRestricted = fetchError { return true }
            return false
        }
    }

    @Test("does not fall back to expired key when provider reports restricted access")
    func doesNotFallbackToExpiredKeyWhenCloudKitIsRestricted() async {
        // Given: cache has an expired key and provider reports restricted access.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expiredKey = APIKey(rawValue: "expired-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.expired(expiredKey)))

        let provider = FailingKeyProvider(error: FetchKeyError.cloudKitRestricted)
        let reader = reader(provider: provider, state: storageState)

        // When/Then: restricted access propagates and expired key is not used.
        await #expect {
            try await reader.apiKey(named: keyName, expiresMinutes: 60)
        } throws: { error in
            guard let fetchError = error as? FetchKeyError else { return false }
            if case .cloudKitRestricted = fetchError { return true }
            return false
        }
    }

    @Test("falls back to expired key when provider reports transient failure")
    func fallsBackOnTransientFailure() async throws {
        // Given: cache has an expired key and provider throws a transient error
        // (serviceUnavailable maps to networkUnavailable at the provider layer).
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expiredKey = APIKey(rawValue: "expired-\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.expired(expiredKey)))

        let provider = FailingKeyProvider(error: FetchKeyError.networkUnavailable)
        let reader = reader(provider: provider, state: storageState)

        // When: requesting the key and the provider fails transiently.
        let result = try await reader.apiKey(named: keyName, expiresMinutes: 60)

        // Then: the expired key is returned as a fallback.
        #expect(result.rawValue == expiredKey.rawValue)
    }

    @Test("clearCache removes cached key")
    func clearCacheRemovesCachedKey() async {
        // Given: a reader with a test storage backend.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let storageState = TestStorageState(loadBehavior: .error(LoadError.keyDoesNotExist))

        let provider = SucceedingKeyProvider(apiKey: APIKey(rawValue: "unused"))
        let reader = reader(provider: provider, state: storageState)

        // When: clearing the cache for a key.
        await reader.clearCache(for: keyName)

        // Then: clear was invoked on the storage.
        #expect(await storageState.clearCallCount == 1)
    }

    @Test("clearCache clears existing cached storage instance")
    func clearCacheClearsExistingCachedStorageInstance() async throws {
        // Given: the first read creates and caches storage instance 0.
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let cachedKey = APIKey(rawValue: "cached-\(UUID().uuidString)")
        let probe = StorageFactoryProbe()
        let storageID = 0

        let provider = FailingKeyProvider(error: FetchKeyError.networkUnavailable)
        let reader = APIKeyReader(
            keyProvider: provider,
            localStorageFactory: { _ in
                IdentifiedCachedKeyStorage(id: storageID, probe: probe, key: cachedKey)
            },
        )

        _ = try await reader.apiKey(named: keyName, expiresMinutes: 60)

        // When: clearing the cache for the same key.
        await reader.clearCache(for: keyName)

        // Then: clear runs against the already cached storage instance (id 0).
        #expect(await probe.clearedIDs() == [0])
    }
}
