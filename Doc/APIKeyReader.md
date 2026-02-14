# APIKeyReader

## Overview

APIKeyReader is the main entry point for fetching API keys from CloudKit with intelligent caching and error resilience. It uses Swift's actor model to provide thread-safe key management with automatic deduplication of concurrent requests.

## Key Design Decisions

### Actor Isolation for Thread Safety

The `APIKeyReader` type is an actor, ensuring all mutable state is isolated to a single execution context:

```swift
public actor APIKeyReader: Observable {
    private var keyFetchTask: [APIKeyName: Task<APIKey, Error>] = [:]
    // ...
}
```

This eliminates data races when:
- Multiple views request the same key simultaneously during app launch
- Background tasks refresh keys while the UI is active
- SwiftUI view updates trigger concurrent fetch attempts

The alternative approaches have significant drawbacks:

**Manual locking with locks or semaphores:**
- Error-prone: easy to forget locks or create deadlocks
- Doesn't integrate with Swift Concurrency's cooperative thread pool
- Requires careful lock ordering to avoid priority inversions

**Serial DispatchQueue:**
- Uses GCD, which doesn't compose well with async/await
- Requires bridging with continuation APIs
- Doesn't benefit from Swift 6's data race safety checks

**@MainActor:**
- Forces all key fetches onto the main thread
- Network calls would block UI interactions
- Poor performance for background key refresh

Actor isolation provides:
- Automatic data race prevention enforced by the compiler
- Cooperative scheduling that doesn't block any particular thread
- Seamless integration with CloudKit's async APIs
- No manual lock management

### Task Deduplication via Dictionary

Concurrent requests for the same key share a single CloudKit fetch task internally.
The actor keeps a `keyFetchTask` dictionary, so repeated requests for the same key
while a fetch is in progress attach to the same task instead of launching extra
CloudKit lookups.

This pattern prevents CloudKit query storms during app launch when multiple views might request the same key simultaneously. Without deduplication:

1. **Unnecessary network load** — 5 views requesting the same key would trigger 5 CloudKit queries
2. **CloudKit rate limiting** — Burst requests could hit API rate limits, causing throttling
3. **Wasted battery** — Redundant radio usage for identical data
4. **Slower response** — 5 concurrent queries compete for bandwidth instead of sharing one

The Task-based approach works because:
- Swift Tasks are value types that can be shared across `await` suspension points
- Multiple callers awaiting the same Task automatically share the result or error
- Task cancellation propagates correctly if all callers cancel
- The actor guarantees the dictionary is only accessed from one context at a time

Alternative approaches:
- **Combine publishers** — Would require maintaining subscriptions and managing cancellation manually
- **AsyncSequence with shared iteration** — More complex, doesn't naturally represent single-value fetch
- **Callback-based deduplication** — Doesn't compose with async/await, requires manual completion tracking

### Observable Conformance for SwiftUI Integration

The actor conforms to `Observable` (via the `@Observable` macro in modern Swift):

```swift
public actor APIKeyReader: Observable
```

This allows SwiftUI views to observe the actor's state without manual publisher setup:

```swift
@State private var apiKeyReader: APIKeyReader

var body: some View {
    Text("Ready")
        .task {
            let key = try? await apiKeyReader.apiKey(named: .openWeatherMap, expiresMinutes: 60)
            // Use key
        }
}
```

The Observable conformance provides:
- Automatic view invalidation when fetch completes
- Integration with SwiftUI's dependency injection
- Compatibility with `@Environment` and `@State`

### Internal Fetch Helpers

`apiKey(named:expiresMinutes:)` coordinates cache reads, transient fallback, and task coordination through small private helper methods.

```swift
public func apiKey(
    named apiKeyName: APIKeyName,
    expiresMinutes: Int,
) async throws -> APIKey
```

This pattern keeps related logic together while avoiding:
- Polluting the actor's method namespace with implementation details
- Exposing internal helpers that shouldn't be public or even private members
- Creating unnecessary actor re-entrancy (local functions don't cross actor boundaries)

Local functions have access to the enclosing scope's variables (`expiredKey`, `localStorage`, etc.), reducing parameter passing overhead.

## Usage

### Basic Fetch

```swift
let apiKeyReader = APIKeyReader(containerIdentifier: "iCloud.com.example.app")

let key = try await apiKeyReader.apiKey(
    named: .openWeatherMap,
    expiresMinutes: 60
)
// Use key with third-party API
```

### Error Handling

```swift
do {
    let key = try await apiKeyReader.apiKey(named: .mapbox, expiresMinutes: 120)
    configureMapView(with: key)
} catch FetchKeyError.networkUnavailable {
    // User is offline — show cached content or error message
    showOfflineAlert()
} catch FetchKeyError.recordNotFound {
    // Developer misconfiguration — key doesn't exist in CloudKit
    assertionFailure("Missing API key in CloudKit configuration")
} catch {
    // Other errors
    showGenericError()
}
```

### SwiftUI Integration

```swift
struct WeatherView: View {
    @State private var apiKeyReader: APIKeyReader
    @State private var weatherData: WeatherData?

    var body: some View {
        WeatherContent(data: weatherData)
            .task {
                do {
                    let key = try await apiKeyReader.apiKey(
                        named: .openWeatherMap,
                        expiresMinutes: 60
                    )
                    weatherData = try await fetchWeather(using: key)
                } catch {
                    // Handle error
                }
            }
    }
}
```

### Cache Clearing

```swift
@Environment(APIKeyReader.self) private var apiKeyReader

func rotateCredential() async {
    await apiKeyReader.clearCache(for: .openWeatherMap)
}
```

## Architecture

```mermaid
sequenceDiagram
    participant App
    participant APIKeyReader
    participant LocalStorage
    participant Keychain
    participant CloudKit

    App->>APIKeyReader: apiKey(named: .openWeatherMap)
    APIKeyReader->>LocalStorage: load()
    LocalStorage->>Keychain: SecItemCopyMatching

    alt Fresh key in cache
        Keychain-->>LocalStorage: Data
        LocalStorage-->>APIKeyReader: APIKey
        APIKeyReader-->>App: APIKey (cached)
    else Expired key in cache
        Keychain-->>LocalStorage: Data (expired)
        LocalStorage-->>APIKeyReader: LoadError.expired(APIKey)
        APIKeyReader->>CloudKit: fetchAPIKey()

        alt CloudKit success
            CloudKit-->>APIKeyReader: APIKey
            APIKeyReader->>LocalStorage: save(value, expiresMinutes)
            LocalStorage->>Keychain: SecItemUpdate/Add
            APIKeyReader-->>App: APIKey (fresh)
        else CloudKit failure
            CloudKit-->>APIKeyReader: Error
            APIKeyReader-->>App: APIKey (expired fallback)
        end
    else No cache
        Keychain-->>LocalStorage: nil
        LocalStorage-->>APIKeyReader: LoadError.keyDoesNotExist
        APIKeyReader->>CloudKit: fetchAPIKey()
        CloudKit-->>APIKeyReader: APIKey
        APIKeyReader->>LocalStorage: save(value, expiresMinutes)
        APIKeyReader-->>App: APIKey (fresh)
    end

    style App fill:#2d3748,stroke:#4a5568,stroke-width:2px,color:#ffffff
    style APIKeyReader fill:#1a365d,stroke:#2c5282,stroke-width:2px,color:#ffffff
    style LocalStorage fill:#22543d,stroke:#2f855a,stroke-width:2px,color:#ffffff
    style Keychain fill:#744210,stroke:#975a16,stroke-width:2px,color:#ffffff
    style CloudKit fill:#2b6cb0,stroke:#2c5282,stroke-width:2px,color:#ffffff
```

## Performance Characteristics

**First fetch (cold cache):**
- Keychain read attempt: ~1ms
- CloudKit query: 200-500ms (network dependent)
- Keychain write: ~2ms
- Total: ~200-500ms

**Subsequent fetch (warm cache):**
- Keychain read: ~1ms
- No network request
- Total: ~1ms

**Concurrent requests (same key):**
- First request triggers CloudKit fetch
- Subsequent requests await same Task
- All callers resolve simultaneously when Task completes
- No additional network overhead

## See Also

- [LocalStorage](LocalStorage.md) — Keychain-based persistent cache
- [Error Resilience](ErrorResilience.md) — Fallback strategy and error handling
- [CloudKitKeyProvider](CloudKitKeyProvider.md) — CloudKit query implementation
