# Protocols

## Overview

APIKeyReader uses protocol-based abstraction to decouple CloudKit and Keychain implementations from the coordination logic. This enables testing, future extensibility, and clear separation of concerns.

Both `KeyProvider` and `CachedKeyStorage` protocols are defined at the package root (`Sources/APIKeyReader/`), adjacent to the `APIKeyReader` actor that uses them. This placement emphasizes their role as core contracts in the architecture.

## Key Design Decisions

### Why KeyProvider Protocol

`KeyProvider` defines the contract for fetching keys from a remote source:

```swift
protocol KeyProvider: Sendable {
    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey
}
```

**Why use a protocol instead of directly depending on CloudKitKeyProvider?**

1. **Testing flexibility** — Tests can inject mock providers that return predetermined keys or failures:

```swift
struct MockKeyProvider: KeyProvider {
    var result: Result<APIKey, Error>

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        try result.get()
    }
}

let reader = APIKeyReader(keyProvider: MockKeyProvider(result: .success(mockKey)))
```

2. **Future extensibility** — Different backends (HTTP API, local file) can replace CloudKit without changing `APIKeyReader`:

```swift
struct HTTPKeyProvider: KeyProvider {
    let baseURL: URL

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        // Fetch from REST API
    }
}
```

3. **Separation of concerns** — CloudKit retry logic, error mapping, and schema details stay in `CloudKitKeyProvider`, not polluting the coordinator

Without the protocol, `APIKeyReader` would be tightly coupled to CloudKit, making it impossible to test without network access or swap backends.

### Why CachedKeyStorage Protocol

`CachedKeyStorage` defines the contract for local caching:

```swift
protocol CachedKeyStorage: Sendable {
    func load() async throws -> APIKey
    func clear() async
    func save(value: APIKey?, expiresMinutes: Int) async
}
```

**Why abstract the cache layer?**

1. **Test isolation** — Tests can use in-memory storage to avoid Keychain side effects:

```swift
actor InMemoryStorage: CachedKeyStorage {
    private var cache: [String: (key: APIKey, expiry: Date)] = [:]

    func load() async throws -> APIKey {
        // Read from dictionary
    }

    func save(value: APIKey?, expiresMinutes: Int) async {
        // Write to dictionary
    }
}
```

2. **Platform flexibility** — Different platforms can use different storage (UserDefaults on watchOS, file-based on Linux)

3. **Expiration abstraction** — The protocol hides `SavedAPIKey` encoding/decoding details from `APIKeyReader`

Without the protocol, `APIKeyReader` would directly depend on Keychain APIs, making tests brittle and platform-specific.

### Why Sendable Conformance

Both protocols require `Sendable` conformance:

```swift
protocol KeyProvider: Sendable { }
protocol CachedKeyStorage: Sendable { }
```

**Rationale:**

- `APIKeyReader` is an **actor** that holds instances of these types
- Swift Concurrency requires values crossing actor boundaries to be `Sendable`
- Conforming to `Sendable` guarantees implementations are safe for concurrent access

Without `Sendable`, the compiler would error:

```
error: stored property 'keyProvider' of 'Sendable'-conforming actor 'APIKeyReader' has non-sendable type 'any KeyProvider'
```

### Why load() Throws Instead of Returning Optional

`CachedKeyStorage.load()` throws errors rather than returning `APIKey?`:

```swift
func load() async throws -> APIKey
```

**Why not `func load() async -> APIKey?`?**

Returning `nil` would collapse distinct failure modes:
- Key doesn't exist
- Key is expired
- Keychain is corrupted
- Keychain access denied

Throwing structured errors (`LoadError`) allows `APIKeyReader` to distinguish these cases and react appropriately:

```swift
catch LoadError.expired(let key):
    // Use key as fallback
catch LoadError.keyDoesNotExist:
    // Fetch from network
catch LoadError.decodeError:
    // Clear corrupted cache
catch LoadError.keychainError(let error):
    // Log and fall back to network
```

### Why save() Accepts Optional Values

`CachedKeyStorage.save()` accepts `APIKey?` instead of just `APIKey`:

```swift
func save(value: APIKey?, expiresMinutes: Int) async
```

**Why allow `nil`?**

Passing `nil` provides a **clear intent** signal: clear the cache. Compare:

```swift
// With optional:
await storage.save(value: nil, expiresMinutes: 0)  // Intent: clear

// Without optional:
await storage.save(value: APIKey(rawValue: ""), expiresMinutes: 0)  // Unclear intent
await storage.clear()  // Requires separate method call
```

This design consolidates save/clear logic into a single method while maintaining clarity.

### Why Protocols Don't Expose SavedAPIKey

`SavedAPIKey` (the internal type wrapping `APIKey` + expiration metadata) is **not** part of the protocol:

```swift
// Internal to LocalStorage:
struct SavedAPIKey: Codable {
    let key: APIKey
    let updated: Date
    let expiresMinutes: Int
}

// Protocol only exposes APIKey:
protocol CachedKeyStorage {
    func load() async throws -> APIKey
}
```

**Why hide SavedAPIKey?**

1. **Implementation detail** — Different storage backends may track expiration differently (file modification time, database timestamp)
2. **Simpler protocol** — Callers only care about `APIKey`, not the wrapper structure
3. **Flexibility** — Implementations can change internal encoding without protocol changes

Exposing `SavedAPIKey` would couple the protocol to Keychain's encoding strategy.

## Protocol Conformance

### CloudKitKeyProvider Conformance

```swift
extension CloudKitKeyProvider: KeyProvider {}
```

`CloudKitKeyProvider` conforms to `KeyProvider` via extension. The implementation is in the main type:

```swift
struct CloudKitKeyProvider: Sendable {
    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        // CloudKit query logic
    }
}
```

This pattern keeps the protocol conformance declaration separate from the implementation.

### LocalStorage Conformance

```swift
struct LocalStorage: CachedKeyStorage {
    func load() async throws -> APIKey {
        // Read from KeychainStorage
        // Decode SavedAPIKey
        // Check expiration
    }

    func save(value: APIKey?, expiresMinutes: Int) async {
        // Encode SavedAPIKey
        // Write to KeychainStorage
    }

    func clear() async {
        // Delete from KeychainStorage
    }
}
```

`LocalStorage` conforms directly because the protocol is core to its purpose.

## Dependency Injection Pattern

`APIKeyReader` uses dependency injection to accept protocol-conforming types:

```swift
public actor APIKeyReader {
    private let keyProvider: any KeyProvider
    private let localStorageFactory: @Sendable (APIKeyName) -> any CachedKeyStorage

    init(
        keyProvider: any KeyProvider,
        localStorageFactory: @escaping @Sendable (APIKeyName) -> any CachedKeyStorage = { LocalStorage(key: $0) }
    ) {
        self.keyProvider = keyProvider
        self.localStorageFactory = localStorageFactory
    }
}
```

**Key points:**

- **`any KeyProvider`** — Existential type, allows runtime polymorphism
- **Factory pattern** — Storage is created per-key on demand, not at initialization
- **`@Sendable` closure** — Factory must be safe to call from the actor
- **Default values** — Production code uses `CloudKitKeyProvider` and `LocalStorage` without passing them

### Why Factory Instead of Direct Injection

Storage is created via a factory function rather than injecting storage instances directly:

```swift
// Current design (factory):
let localStorageFactory: @Sendable (APIKeyName) -> any CachedKeyStorage

// Alternative (direct injection):
let storage: any CachedKeyStorage  // ❌ Doesn't scale to multiple keys
```

**Why use a factory?**

- `APIKeyReader` manages **multiple keys** (e.g., `openWeatherMap`, `mapboxAPI`)
- Each key needs its own storage instance (different Keychain accounts)
- The factory creates storage lazily and caches it in `storageCache`

Without the factory, callers would need to pre-create storage for all possible keys, defeating lazy initialization.

## Testing Example

```swift
@Test func testExpiredKeyFallback() async throws {
    let expiredKey = APIKey(rawValue: "expired-key-123")
    let mockStorage = MockStorage(loadResult: .failure(LoadError.expired(expiredKey)))
    let mockProvider = MockKeyProvider(fetchResult: .failure(FetchKeyError.networkUnavailable))

    let reader = APIKeyReader(
        keyProvider: mockProvider,
        localStorageFactory: { _ in mockStorage }
    )

    let result = try await reader.apiKey(named: .openWeatherMap, expiresMinutes: 60)
    #expect(result == expiredKey)
}
```

Without protocols, this test would require:
- Mocking CloudKit container (complex, fragile)
- Mocking Keychain operations (requires code injection or swizzling)
- Network isolation (flaky tests)

## See Also

- [Architecture](Architecture.md) — Why protocol-based design
- [Testing](Testing.md) — Mock implementations for tests
