# ``APIKeyReader``

Securely fetch and cache API keys from CloudKit with automatic offline fallback.

## Overview

APIKeyReader provides a simple, type-safe way to manage API keys in your iOS and macOS applications. Keys are stored in CloudKit, fetched on demand, and cached locally in the Keychain for quick access and offline resilience.

### Key Features

- **Type-safe key identifiers** — Use compile-time validated `APIKeyName` values instead of string literals
- **Intelligent caching** — Keys are cached in the Keychain with configurable expiration times
- **Offline resilience** — Expired cached keys are returned when CloudKit is unavailable
- **Concurrent request deduplication** — Multiple simultaneous requests for the same key share a single CloudKit fetch
- **Thread-safe** — Actor-based design prevents data races and ensures safe concurrent access

### At a Glance

```swift
import APIKeyReader

// Initialize with your CloudKit container
let reader = APIKeyReader(containerIdentifier: "iCloud.com.example.app")

// Fetch a key (cached for 60 minutes)
let apiKey = try await reader.apiKey(named: .openWeatherMap, expiresMinutes: 60)

// Use the key with your API client
let weather = try await weatherClient.fetchWeather(apiKey: apiKey.rawValue)
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``APIKeyReader/apiKey(named:expiresMinutes:)``
- ``APIKeyName``
- ``APIKey``

### Error Handling

- ``FetchKeyError``
- <doc:ErrorHandling>

### Cache Management

- ``APIKeyReader/clearCache(for:)``
- <doc:CacheStrategy>

### Advanced Usage

- <doc:SwiftUIIntegration>
- <doc:TestingStrategies>
