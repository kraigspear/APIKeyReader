import Foundation
import Testing
@testable import APIKeyReader

@Suite("LocalStorage")
struct LocalStorageTests {
    private func withBackend<T>(
        _ operation: @escaping (InMemoryKeychainBackend) async throws -> T,
    ) async throws -> T {
        let backend = InMemoryKeychainBackend()
        return try await KeychainStorage.withTestBackend(
            load: { account in
                backend.load(account: account)
            },
            save: { data, account in
                backend.save(data: data, account: account)
            },
            clear: { account in
                backend.clear(account: account)
            },
        ) {
            try await operation(backend)
        }
    }

    @Test("loads valid cached API key")
    func loadsValidCacheEntry() async throws {
        let key = APIKeyName(rawValue: "api-key-reader.tests.local.\(UUID().uuidString)")
        let expected = APIKey(rawValue: "cached-key-\(UUID().uuidString)")
        let loaded = try await withBackend { _ in
            let storage = LocalStorage(key: key)
            await storage.save(value: expected, expiresMinutes: 10)
            return try await storage.load()
        }
        #expect(loaded.rawValue == expected.rawValue)
    }

    @Test("throws when cached entry is expired")
    func throwsWhenExpired() async throws {
        let key = APIKeyName(rawValue: "api-key-reader.tests.local.\(UUID().uuidString)")
        try await withBackend { _ in
            let storage = LocalStorage(key: key)
            await storage.save(value: APIKey(rawValue: "expired-key"), expiresMinutes: 0)

            await #expect {
                _ = try await storage.load()
            } throws: { error in
                guard let loadError = error as? LoadError else {
                    return false
                }
                if case .expired = loadError {
                    return true
                }
                return false
            }
        }
    }

    @Test("throws decodeError for corrupted payload")
    func throwsWhenDataCorrupt() async throws {
        let key = APIKeyName(rawValue: "api-key-reader.tests.local.\(UUID().uuidString)")
        try await withBackend { backend in
            _ = backend.save(data: "corrupt".data(using: .utf8)!, account: key.rawValue)
            let storage = LocalStorage(key: key)

            await #expect {
                _ = try await storage.load()
            } throws: { error in
                guard let loadError = error as? LoadError else {
                    return false
                }
                if case .decodeError = loadError {
                    return true
                }
                return false
            }
        }
    }

    @Test("saves nil by clearing entry")
    func saveNilClearsEntry() async throws {
        let key = APIKeyName(rawValue: "api-key-reader.tests.local.\(UUID().uuidString)")
        try await withBackend { _ in
            let storage = LocalStorage(key: key)
            await storage.save(value: APIKey(rawValue: "to-be-cleared"), expiresMinutes: 10)
            await storage.save(value: nil, expiresMinutes: 10)

            await #expect {
                _ = try await storage.load()
            } throws: { error in
                guard let loadError = error as? LoadError else {
                    return false
                }
                if case .keyDoesNotExist = loadError {
                    return true
                }
                return false
            }
        }
    }
}
