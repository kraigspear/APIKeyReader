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

// MARK: - APIKeyReader Tests

@Suite("APIKeyReader")
struct APIKeyReaderTests {
    @Test("fetches from provider when cache is empty")
    func fetchesWhenCacheEmpty() async throws {
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expectedKey = APIKey(rawValue: "fresh-\(UUID().uuidString)")

        let provider = SucceedingKeyProvider(apiKey: expectedKey)
        let reader = APIKeyReader(keyProvider: provider)

        let result = try await reader.apiKey(named: keyName, expiresMinutes: 60)
        #expect(result.rawValue == expectedKey.rawValue)
    }

    @Test("coalesces concurrent fetches for same key")
    func coalescesConcurrentFetchesForSameKey() async throws {
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")
        let expectedKey = APIKey(rawValue: "coalesced-\(UUID().uuidString)")

        let provider = CountingDelayedKeyProvider(
            apiKey: expectedKey,
            delay: .milliseconds(100),
        )
        let reader = APIKeyReader(keyProvider: provider)

        async let first = reader.apiKey(named: keyName, expiresMinutes: 60)
        async let second = reader.apiKey(named: keyName, expiresMinutes: 60)
        let (firstKey, secondKey) = try await (first, second)

        #expect(firstKey.rawValue == expectedKey.rawValue)
        #expect(secondKey.rawValue == expectedKey.rawValue)
        #expect(await provider.fetchCount == 1)
    }

    @Test("throws when provider fails and no cached key exists")
    func throwsWhenNoFallback() async {
        let keyName = APIKeyName(rawValue: "api-key-reader.tests.\(UUID().uuidString)")

        let provider = FailingKeyProvider(error: FetchKeyError.networkUnavailable)
        let reader = APIKeyReader(keyProvider: provider)

        await #expect {
            try await reader.apiKey(named: keyName, expiresMinutes: 60)
        } throws: { error in
            guard let fetchError = error as? FetchKeyError else { return false }
            if case .networkUnavailable = fetchError { return true }
            return false
        }
    }
}
