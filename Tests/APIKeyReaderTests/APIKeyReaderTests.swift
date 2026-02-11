import Foundation
import Testing
@testable import APIKeyReader

// MARK: - Test Doubles

struct SucceedingKeyProvider: KeyProvider {
    let apiKey: APIKey

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        apiKey
    }
}

struct FailingKeyProvider: KeyProvider {
    let error: Error

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        throw error
    }
}

actor CountingDelayedKeyProvider: KeyProvider {
    let apiKey: APIKey
    let delay: Duration
    private(set) var fetchCount = 0

    init(apiKey: APIKey, delay: Duration) {
        self.apiKey = apiKey
        self.delay = delay
    }

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        fetchCount += 1
        try await Task.sleep(for: delay)
        return apiKey
    }
}

// MARK: - Test Helpers

enum LoadBehavior {
    case value(APIKey)
    case error(any Error)
}

final class TestStorageState: @unchecked Sendable {
    var loadBehavior: LoadBehavior
    var clearCallCount = 0
    var saveCallCount = 0
    var lastSavedKey: APIKey?

    init(loadBehavior: LoadBehavior) {
        self.loadBehavior = loadBehavior
    }
}

struct TestCachedKeyStorage: CachedKeyStorage, @unchecked Sendable {
    let state: TestStorageState

    func load() throws -> APIKey {
        switch state.loadBehavior {
        case let .value(key):
            return key
        case let .error(error):
            throw error
        }
    }

    func clear() {
        state.clearCallCount += 1
        state.loadBehavior = .error(LoadError.keyDoesNotExist)
    }

    func save(value: APIKey?, expiresMinutes _: Int) {
        state.saveCallCount += 1
        state.lastSavedKey = value
    }
}

private func reader(
    provider: any KeyProvider,
    state: TestStorageState,
) -> APIKeyReader {
    APIKeyReader(
        keyProvider: provider,
        localStorageFactory: { _ in
            TestCachedKeyStorage(state: state)
        },
    )
}

private func isNetworkUnavailable(_ error: any Error) -> Bool {
    guard let fetchError = error as? FetchKeyError else { return false }
    if case .networkUnavailable = fetchError { return true }
    return false
}

// MARK: - APIKeyReader Tests

@Suite("APIKeyReader")
struct APIKeyReaderTests {
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
        #expect(storageState.saveCallCount == 1)
        #expect(storageState.lastSavedKey?.rawValue == expectedKey.rawValue)
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
            isNetworkUnavailable(error)
        }

        // Then: malformed cached value has been removed from local storage.
        #expect(storageState.clearCallCount == 1)
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
        #expect(storageState.clearCallCount == 1)
    }

}
