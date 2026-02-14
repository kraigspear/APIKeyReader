# Cache Strategy

Understand how APIKeyReader caches keys locally and when to clear the cache.

## Overview

APIKeyReader uses the Keychain to cache API keys locally, reducing network requests and enabling offline functionality. Understanding cache behavior helps you choose appropriate expiration times and know when to clear the cache.

## How Caching Works

When you request an API key, APIKeyReader follows this process:

1. **Check Keychain** — Look for a cached key with the specified name
2. **Validate expiration** — Check if the cached key has expired
3. **Return or fetch** — Return valid key immediately, or fetch from CloudKit if expired/missing
4. **Update cache** — Store the fetched key with a new expiration timestamp

### Cache Hit (Valid)

If a valid key exists in the cache:

```swift
let apiKey = try await reader.apiKey(named: .weather, expiresMinutes: 60)
// Returns immediately from Keychain (~1ms)
// No network request
```

**Performance:** ~1ms (Keychain read only)

### Cache Miss or Expired

If no key exists or the cached key has expired:

```swift
let apiKey = try await reader.apiKey(named: .weather, expiresMinutes: 60)
// 1. Reads Keychain (expired or missing)
// 2. Fetches from CloudKit (~200-500ms)
// 3. Writes to Keychain
// 4. Returns fresh key
```

**Performance:** ~200-500ms (includes network request)

### Network Failure Fallback

If CloudKit fetch fails but an expired key exists:

```swift
let apiKey = try await reader.apiKey(named: .weather, expiresMinutes: 60)
// 1. Reads Keychain (expired)
// 2. Attempts CloudKit fetch (fails)
// 3. Returns expired key (graceful degradation)
```

The expired key is returned without throwing an error, allowing your app to continue functioning offline.

## Choosing Expiration Times

The `expiresMinutes` parameter controls how long a key remains valid in the cache. Choose a value based on your key rotation frequency and offline requirements.

### Recommended Values

| Expiration | Use Case | Trade-offs |
|------------|----------|------------|
| **15-30 minutes** | Frequently rotated keys | Fresh keys, more network requests |
| **60 minutes** | Standard usage | Balanced freshness and performance |
| **120-360 minutes** | Infrequently rotated keys | Fewer requests, keys may be stale |
| **720-1440 minutes** | Static keys, offline-first apps | Maximum offline support, oldest keys |

### Example Configurations

**Frequently updated service:**

```swift
// Check for new keys every 30 minutes
let apiKey = try await reader.apiKey(
    named: .liveUpdates,
    expiresMinutes: 30
)
```

**Standard usage:**

```swift
// Typical 1-hour cache
let apiKey = try await reader.apiKey(
    named: .weather,
    expiresMinutes: 60
)
```

**Offline-first app:**

```swift
// Cache for 24 hours to support extended offline use
let apiKey = try await reader.apiKey(
    named: .maps,
    expiresMinutes: 1440
)
```

## Cache Storage

Keys are stored in the Keychain with these characteristics:

- **Security** — Keychain items are encrypted and protected by iOS
- **Persistence** — Survives app restarts and device reboots
- **Access control** — Only your app can access its own Keychain items
- **Backup** — Not included in iCloud backups or device backups

### What Gets Cached

Each cached entry stores:
- The API key value
- An expiration timestamp (current time + `expiresMinutes`)

### Cache Size

Keychain storage is minimal. A typical API key entry uses less than 1KB:
- Key value: ~50-200 bytes
- Metadata: ~100 bytes

## Clearing the Cache

Use ``APIKeyReader/clearCache(for:)`` to remove a cached key from the Keychain.

### When to Clear the Cache

**After user logout:**

```swift
func logout() async {
    await apiKeyReader.clearCache(for: .userProfile)
    await apiKeyReader.clearCache(for: .userContent)
    // Clear other user-specific keys
}
```

**After account switching:**

```swift
func switchAccount(to newAccount: Account) async {
    // Clear all cached keys for the old account
    await apiKeyReader.clearCache(for: .userAPI)

    // Next fetch will use the new account's CloudKit container
    let key = try await apiKeyReader.apiKey(
        named: .userAPI,
        expiresMinutes: 60
    )
}
```

**When rotating a key:**

```swift
func rotateAPIKey() async {
    // Force immediate refresh from CloudKit
    await apiKeyReader.clearCache(for: .service)

    // Next fetch will get the new key
    let freshKey = try await apiKeyReader.apiKey(
        named: .service,
        expiresMinutes: 60
    )
}
```

**Testing scenarios:**

```swift
func testKeyFetch() async throws {
    // Start with clean state
    await apiKeyReader.clearCache(for: .testKey)

    // Test fresh fetch behavior
    let key = try await apiKeyReader.apiKey(
        named: .testKey,
        expiresMinutes: 5
    )
}
```

### What Happens After Clearing

After clearing the cache:
1. The Keychain entry is deleted
2. Next request will fetch from CloudKit
3. New cache entry is created with fresh expiration

## Request Deduplication

APIKeyReader automatically deduplicates concurrent requests for the same key, even during the first fetch.

### How It Works

```swift
// Multiple views request the same key simultaneously
Task {
    let key1 = try await reader.apiKey(named: .weather, expiresMinutes: 60)
}
Task {
    let key2 = try await reader.apiKey(named: .weather, expiresMinutes: 60)
}
Task {
    let key3 = try await reader.apiKey(named: .weather, expiresMinutes: 60)
}

// Only ONE CloudKit fetch is performed
// All three tasks receive the same result
```

This prevents unnecessary network requests and CloudKit API quota consumption.

### Benefits

- **Reduced network traffic** — One fetch instead of N concurrent fetches
- **Lower latency** — No competition for bandwidth
- **CloudKit quota preservation** — Avoids rate limiting from burst requests
- **Battery efficiency** — Minimizes radio usage

## Complete Example

Here's a comprehensive example showing cache management:

```swift
import APIKeyReader

actor WeatherService {
    private let apiKeyReader: APIKeyReader

    init(containerIdentifier: String) {
        self.apiKeyReader = APIKeyReader(
            containerIdentifier: containerIdentifier
        )
    }

    func fetchWeather(for location: String) async throws -> WeatherData {
        // Use 1-hour cache for weather API key
        let apiKey = try await apiKeyReader.apiKey(
            named: .openWeatherMap,
            expiresMinutes: 60
        )

        return try await makeWeatherRequest(
            location: location,
            apiKey: apiKey.rawValue
        )
    }

    func rotateAPIKey() async {
        // Force refresh from CloudKit
        await apiKeyReader.clearCache(for: .openWeatherMap)
    }

    func resetForNewUser() async {
        // Clear all cached keys when switching users
        await apiKeyReader.clearCache(for: .openWeatherMap)
        await apiKeyReader.clearCache(for: .mapbox)
    }
}
```

## Best Practices

### Match Expiration to Key Rotation

Set `expiresMinutes` based on how often you rotate keys in CloudKit:

```swift
// If you rotate keys daily
let apiKey = try await reader.apiKey(
    named: .dailyRotated,
    expiresMinutes: 360  // 6 hours - plenty of margin
)

// If keys are static
let apiKey = try await reader.apiKey(
    named: .static,
    expiresMinutes: 1440  // 24 hours
)
```

### Longer Expiration for Offline Support

If offline functionality is critical, use longer expiration times:

```swift
// Support 24 hours offline
let apiKey = try await reader.apiKey(
    named: .essential,
    expiresMinutes: 1440
)
```

Remember: Expired keys are still usable as fallbacks when the network is unavailable.

### Don't Over-Clear the Cache

Avoid clearing the cache unnecessarily:

```swift
// ❌ Don't clear on every app launch
func applicationDidBecomeActive() {
    await clearAllCaches()  // Unnecessary network requests
}

// ✅ Only clear when needed
func userDidLogout() {
    await apiKeyReader.clearCache(for: .userSpecific)
}
```

### Use Consistent Expiration Times

Use the same expiration value for repeated requests to maintain predictable behavior:

```swift
// ✅ Consistent
let key1 = try await reader.apiKey(named: .weather, expiresMinutes: 60)
// Later...
let key2 = try await reader.apiKey(named: .weather, expiresMinutes: 60)

// ❌ Inconsistent - may cause unexpected refreshes
let key1 = try await reader.apiKey(named: .weather, expiresMinutes: 60)
let key2 = try await reader.apiKey(named: .weather, expiresMinutes: 30)
```

## See Also

- ``APIKeyReader/clearCache(for:)``
- ``APIKeyReader/apiKey(named:expiresMinutes:)``
- <doc:ErrorHandling>
