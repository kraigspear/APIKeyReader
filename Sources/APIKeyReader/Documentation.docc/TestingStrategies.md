# Testing Strategies

Learn how to test code that uses APIKeyReader without making real CloudKit requests.

## Overview

Testing code that depends on APIKeyReader requires strategies to avoid real CloudKit calls while still verifying your application logic. This guide covers common testing patterns and best practices.

## Testing Approaches

There are two main strategies for testing code that uses APIKeyReader:

1. **Test against real CloudKit** — Use a dedicated test CloudKit container
2. **Mock the dependencies** — Create test doubles for API keys

Each approach has trade-offs. Choose based on what you're testing.

## Using a Test CloudKit Container

For integration tests that verify CloudKit interaction, use a separate test container.

### Setup Test Container

1. Create a new CloudKit container in the Apple Developer portal (e.g., `iCloud.com.example.app.test`)
2. Configure the same schema as your production container
3. Add test API key records

### Configure Tests

```swift
import Testing
import APIKeyReader

@Suite("APIKeyReader Integration Tests")
struct APIKeyReaderIntegrationTests {
    let reader = APIKeyReader(
        containerIdentifier: "iCloud.com.example.app.test"
    )

    @Test func fetchValidKey() async throws {
        let apiKey = try await reader.apiKey(
            named: .testKey,
            expiresMinutes: 5
        )

        #expect(apiKey.rawValue.isEmpty == false)
    }

    @Test func cachesKeyBetweenRequests() async throws {
        // First fetch
        let key1 = try await reader.apiKey(
            named: .testKey,
            expiresMinutes: 60
        )

        // Second fetch should use cache
        let key2 = try await reader.apiKey(
            named: .testKey,
            expiresMinutes: 60
        )

        #expect(key1.rawValue == key2.rawValue)
    }

    @Test func clearsCache() async throws {
        // Prime the cache
        _ = try await reader.apiKey(
            named: .testKey,
            expiresMinutes: 60
        )

        // Clear it
        await reader.clearCache(for: .testKey)

        // Next fetch will go to CloudKit
        _ = try await reader.apiKey(
            named: .testKey,
            expiresMinutes: 60
        )
        // Test passes if no error
    }
}
```

### Benefits

- **Real behavior** — Tests actual CloudKit integration
- **Catch configuration issues** — Schema problems surface early
- **End-to-end validation** — Entire flow is tested

### Limitations

- **Requires network** — Tests fail when offline
- **Slower** — Network latency adds time
- **CloudKit dependency** — Tests depend on external service availability

## Mocking for Unit Tests

For fast unit tests that focus on your application logic, mock the API key response.

### Create Test Extensions

Define known test keys:

```swift
#if DEBUG
import APIKeyReader

extension APIKeyName {
    static let testWeather = APIKeyName(rawValue: "TestWeather")
    static let testMaps = APIKeyName(rawValue: "TestMaps")
}

extension APIKey {
    static let testValue = APIKey(rawValue: "test-key-12345")
    static let testWeather = APIKey(rawValue: "weather-test-key")
    static let testMaps = APIKey(rawValue: "maps-test-key")
}
#endif
```

### Dependency Injection

Structure your code to accept ``APIKeyReader`` as a dependency:

```swift
actor WeatherService {
    private let apiKeyReader: APIKeyReader

    init(apiKeyReader: APIKeyReader) {
        self.apiKeyReader = apiKeyReader
    }

    func fetchWeather(for city: String) async throws -> WeatherData {
        let apiKey = try await apiKeyReader.apiKey(
            named: .openWeatherMap,
            expiresMinutes: 60
        )

        return try await performRequest(city: city, apiKey: apiKey.rawValue)
    }
}
```

### Test with Real Instance

```swift
import Testing
import APIKeyReader

@Suite("Weather Service Tests")
struct WeatherServiceTests {
    let testReader = APIKeyReader(
        containerIdentifier: "iCloud.com.example.app.test"
    )

    @Test func fetchesWeatherWithValidKey() async throws {
        let service = WeatherService(apiKeyReader: testReader)

        let weather = try await service.fetchWeather(for: "London")

        #expect(weather.city == "London")
    }
}
```

## Testing Error Handling

Verify your code handles different ``FetchKeyError`` cases correctly.

### Network Unavailable

Test offline behavior:

```swift
@Test func handlesOfflineScenario() async throws {
    let service = WeatherService(apiKeyReader: testReader)

    // Simulate airplane mode by using a non-existent container
    let offlineReader = APIKeyReader(
        containerIdentifier: "iCloud.invalid.container"
    )
    let offlineService = WeatherService(apiKeyReader: offlineReader)

    await #expect(throws: FetchKeyError.self) {
        try await offlineService.fetchWeather(for: "London")
    }
}
```

### Record Not Found

Test missing key scenarios:

```swift
@Test func handlesRecordNotFound() async throws {
    await #expect(throws: FetchKeyError.recordNotFound) {
        _ = try await testReader.apiKey(
            named: APIKeyName(rawValue: "NonExistentKey"),
            expiresMinutes: 5
        )
    }
}
```

## Testing Cache Behavior

Verify caching works as expected.

### Cache Expiration

```swift
@Test func respects CacheExpiration() async throws {
    // Set very short expiration
    let key1 = try await testReader.apiKey(
        named: .testKey,
        expiresMinutes: 0  // Expires immediately
    )

    // Wait a moment
    try await Task.sleep(for: .seconds(1))

    // Should fetch fresh key
    let key2 = try await testReader.apiKey(
        named: .testKey,
        expiresMinutes: 60
    )

    // Both keys should be valid
    #expect(key1.rawValue.isEmpty == false)
    #expect(key2.rawValue.isEmpty == false)
}
```

### Cache Isolation

```swift
@Test func keysAreCachedIndependently() async throws {
    let key1 = try await testReader.apiKey(
        named: .testWeather,
        expiresMinutes: 60
    )

    let key2 = try await testReader.apiKey(
        named: .testMaps,
        expiresMinutes: 60
    )

    #expect(key1.rawValue != key2.rawValue)

    // Clear one cache
    await testReader.clearCache(for: .testWeather)

    // Other cache unaffected
    let key3 = try await testReader.apiKey(
        named: .testMaps,
        expiresMinutes: 60
    )

    #expect(key2.rawValue == key3.rawValue)
}
```

## Testing Concurrent Requests

Verify request deduplication works correctly.

```swift
@Test func deduplicates ConcurrentRequests() async throws {
    // Clear cache to ensure fresh fetch
    await testReader.clearCache(for: .testKey)

    // Launch multiple concurrent requests
    async let key1 = testReader.apiKey(named: .testKey, expiresMinutes: 60)
    async let key2 = testReader.apiKey(named: .testKey, expiresMinutes: 60)
    async let key3 = testReader.apiKey(named: .testKey, expiresMinutes: 60)

    let (result1, result2, result3) = try await (key1, key2, key3)

    // All should receive the same key
    #expect(result1.rawValue == result2.rawValue)
    #expect(result2.rawValue == result3.rawValue)
}
```

## Testing SwiftUI Views

Test views that use ``APIKeyReader`` through the environment.

### Setup Test Environment

```swift
import Testing
import SwiftUI
import APIKeyReader

@Suite("Weather View Tests")
struct WeatherViewTests {
    let testReader = APIKeyReader(
        containerIdentifier: "iCloud.com.example.app.test"
    )

    @Test func rendersWeatherData() async throws {
        let view = WeatherView()
            .environment(\.apiKeyReader, testReader)

        // Use ViewInspector or snapshot testing
        // to verify view state
    }
}
```

## Test Fixtures

Create reusable test fixtures for common scenarios.

```swift
#if DEBUG
import APIKeyReader

struct APIKeyReaderTestFixture {
    static let shared = APIKeyReaderTestFixture()

    let reader: APIKeyReader

    private init() {
        reader = APIKeyReader(
            containerIdentifier: "iCloud.com.example.app.test"
        )
    }

    func setupTestKeys() async throws {
        // Prime the cache with known test keys
        _ = try await reader.apiKey(
            named: .testWeather,
            expiresMinutes: 60
        )
        _ = try await reader.apiKey(
            named: .testMaps,
            expiresMinutes: 60
        )
    }

    func clearAllCaches() async {
        await reader.clearCache(for: .testWeather)
        await reader.clearCache(for: .testMaps)
    }
}
#endif
```

Use in tests:

```swift
@Suite("Integration Tests")
struct IntegrationTests {
    let fixture = APIKeyReaderTestFixture.shared

    @Test func completeFetchFlow() async throws {
        await fixture.clearAllCaches()

        let key = try await fixture.reader.apiKey(
            named: .testWeather,
            expiresMinutes: 60
        )

        #expect(key.rawValue.isEmpty == false)
    }
}
```

## Best Practices

### Isolate Each Test

Clear cache before tests to ensure clean state:

```swift
@Test func isolatedTest() async throws {
    // Start fresh
    await testReader.clearCache(for: .testKey)

    // Run test
    let key = try await testReader.apiKey(
        named: .testKey,
        expiresMinutes: 5
    )

    #expect(key.rawValue.isEmpty == false)
}
```

### Use Short Expiration Times

In tests, use short cache expiration to speed up cache-related tests:

```swift
// ✅ Fast tests
let key = try await reader.apiKey(
    named: .test,
    expiresMinutes: 1  // Short for testing
)

// ❌ Slow tests
let key = try await reader.apiKey(
    named: .test,
    expiresMinutes: 1440  // Too long for tests
)
```

### Test Both Success and Failure Paths

Verify error handling:

```swift
@Test func handlesSuccess() async throws {
    let key = try await testReader.apiKey(
        named: .testKey,
        expiresMinutes: 60
    )
    #expect(key.rawValue.isEmpty == false)
}

@Test func handlesFailure() async throws {
    await #expect(throws: FetchKeyError.self) {
        try await testReader.apiKey(
            named: APIKeyName(rawValue: "InvalidKey"),
            expiresMinutes: 60
        )
    }
}
```

### Use Descriptive Key Names

Make test keys obvious:

```swift
// ✅ Clear test purpose
extension APIKeyName {
    static let testCacheExpiration = APIKeyName(rawValue: "TestCacheExpiration")
    static let testNetworkError = APIKeyName(rawValue: "TestNetworkError")
}

// ❌ Unclear
extension APIKeyName {
    static let test1 = APIKeyName(rawValue: "Test1")
    static let test2 = APIKeyName(rawValue: "Test2")
}
```

### Don't Test Implementation Details

Focus on behavior, not internal mechanics:

```swift
// ✅ Tests behavior
@Test func returnsValidAPIKey() async throws {
    let key = try await reader.apiKey(named: .test, expiresMinutes: 60)
    #expect(key.rawValue.isEmpty == false)
}

// ❌ Tests internals
@Test func usesKeychainForStorage() async throws {
    // Don't test that Keychain is used - that's an implementation detail
}
```

## Complete Test Example

Here's a comprehensive test suite:

```swift
import Testing
import APIKeyReader

extension APIKeyName {
    static let integrationTest = APIKeyName(rawValue: "IntegrationTest")
}

@Suite("APIKeyReader Full Test Suite")
struct APIKeyReaderFullTests {
    let reader = APIKeyReader(
        containerIdentifier: "iCloud.com.example.app.test"
    )

    @Test func fetchAndCacheKey() async throws {
        await reader.clearCache(for: .integrationTest)

        let key = try await reader.apiKey(
            named: .integrationTest,
            expiresMinutes: 60
        )

        #expect(key.rawValue.isEmpty == false)
    }

    @Test func usesCachedValue() async throws {
        await reader.clearCache(for: .integrationTest)

        let key1 = try await reader.apiKey(
            named: .integrationTest,
            expiresMinutes: 60
        )

        let key2 = try await reader.apiKey(
            named: .integrationTest,
            expiresMinutes: 60
        )

        #expect(key1.rawValue == key2.rawValue)
    }

    @Test func clearsSpecificKey() async throws {
        _ = try await reader.apiKey(
            named: .integrationTest,
            expiresMinutes: 60
        )

        await reader.clearCache(for: .integrationTest)

        // Should fetch fresh
        let freshKey = try await reader.apiKey(
            named: .integrationTest,
            expiresMinutes: 60
        )

        #expect(freshKey.rawValue.isEmpty == false)
    }

    @Test func handlesInvalidKey() async throws {
        let invalidKey = APIKeyName(rawValue: "DoesNotExist12345")

        await #expect(throws: FetchKeyError.recordNotFound) {
            try await reader.apiKey(
                named: invalidKey,
                expiresMinutes: 5
            )
        }
    }
}
```

## See Also

- ``APIKeyReader``
- ``FetchKeyError``
- <doc:SwiftUIIntegration>
- <doc:ErrorHandling>
