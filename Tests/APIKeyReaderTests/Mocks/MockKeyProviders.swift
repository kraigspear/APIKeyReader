@testable import APIKeyReader

// MARK: - SucceedingKeyProvider

struct SucceedingKeyProvider: KeyProvider {
    let apiKey: APIKey

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        apiKey
    }
}

// MARK: - FailingKeyProvider

struct FailingKeyProvider: KeyProvider {
    let error: Error

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        throw error
    }
}

// MARK: - CountingDelayedKeyProvider

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

// MARK: - MappingKeyProvider

actor MappingKeyProvider: KeyProvider {
    let mapping: [APIKeyName: APIKey]
    let fallback: APIKey
    let delay: Duration
    private(set) var fetchCount = 0

    init(mapping: [APIKeyName: APIKey], fallback: APIKey, delay: Duration = .milliseconds(0)) {
        self.mapping = mapping
        self.fallback = fallback
        self.delay = delay
    }

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        fetchCount += 1
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return mapping[apiKeyName] ?? fallback
    }
}
