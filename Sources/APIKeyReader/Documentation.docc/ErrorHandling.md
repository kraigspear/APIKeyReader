# Error Handling

Learn how to handle errors when fetching API keys and implement graceful degradation strategies.

## Overview

APIKeyReader defines specific error types to help you distinguish between different failure scenarios. Understanding these errors allows you to implement appropriate fallback strategies and provide better user experiences.

## Error Types

All errors thrown by ``APIKeyReader/apiKey(named:expiresMinutes:)`` are of type ``FetchKeyError``:

```swift
do {
    let apiKey = try await apiKeyReader.apiKey(
        named: .openWeatherMap,
        expiresMinutes: 60
    )
} catch let error as FetchKeyError {
    // Handle specific error cases
}
```

### Network Unavailable

Thrown when the device is offline or has poor network connectivity, and no cached key exists.

```swift
catch FetchKeyError.networkUnavailable {
    // User is offline and no cached key is available
    showAlert("Please check your internet connection")
}
```

**When this occurs:**
- Device is in airplane mode
- No network connection available
- No cached key exists (first fetch)

**Recommended action:** Display a message asking the user to check their connection. The error won't occur if a cached key (even expired) is available — the library automatically falls back to the expired key.

### Record Not Found

The API key record doesn't exist in CloudKit with the specified name.

```swift
catch FetchKeyError.recordNotFound {
    // Key was not found in CloudKit
    assertionFailure("Missing API key configuration")
    showDeveloperError("API key not configured")
}
```

**When this occurs:**
- The CloudKit record name doesn't match the `APIKeyName` value
- The record hasn't been created in CloudKit Dashboard
- Wrong CloudKit container is being queried

**Recommended action:** This typically indicates a configuration error during development. Log the error and use assertions to catch it during testing.

### CloudKit Restricted

iCloud access is restricted on the device, typically due to parental controls or MDM policies.

```swift
catch FetchKeyError.cloudKitRestricted {
    // iCloud is disabled or restricted
    showAlert("This app requires iCloud to be enabled")
}
```

**When this occurs:**
- User has disabled iCloud in Settings
- Device is managed with restrictions on iCloud
- Parental controls block iCloud access

**Recommended action:** Inform the user that iCloud access is required and guide them to Settings if appropriate.

### Missing Field

The CloudKit record exists but doesn't have the expected `key` field.

```swift
catch FetchKeyError.missingField(let fieldName) {
    // CloudKit schema is incorrect
    assertionFailure("CloudKit schema missing field: \(fieldName)")
}
```

**When this occurs:**
- CloudKit schema doesn't match expected structure
- Field was deleted from the record
- Wrong record type is being queried

**Recommended action:** This is a development/configuration error. Fix the CloudKit schema to include the `key` field.

### CloudKit Error

A generic CloudKit operation failure that doesn't fall into the other categories.

```swift
catch FetchKeyError.cloudKitError(let error) {
    // Other CloudKit errors
    logger.error("CloudKit error: \(error.localizedDescription)")
}
```

**When this occurs:**
- CloudKit service is temporarily unavailable
- Account quota exceeded
- Other CloudKit-specific issues

**Recommended action:** Log the underlying error for diagnostics and show a generic error message to the user.

## Automatic Fallback Behavior

APIKeyReader automatically uses expired cached keys when CloudKit is unavailable. This provides graceful degradation without explicit error handling:

```swift
// No special error handling needed for offline scenarios
let apiKey = try await apiKeyReader.apiKey(
    named: .openWeatherMap,
    expiresMinutes: 60
)
// Returns expired key if CloudKit fetch fails but cache exists
```

### How Fallback Works

1. **Cache hit (valid)** — Returns cached key immediately
2. **Cache hit (expired)** — Attempts CloudKit fetch
3. **Fetch succeeds** — Returns fresh key, updates cache
4. **Fetch fails** — Returns expired cached key
5. **No cache + fetch fails** — Throws error

This ensures your app continues to function even when:
- Device is offline
- CloudKit is temporarily unavailable
- Network is slow or unreliable

## Comprehensive Error Handling Example

Here's a complete example showing all error cases:

```swift
import APIKeyReader

func fetchWeatherData() async {
    do {
        let apiKey = try await apiKeyReader.apiKey(
            named: .openWeatherMap,
            expiresMinutes: 60
        )

        // Use the key
        let weather = try await weatherService.fetch(using: apiKey.rawValue)
        displayWeather(weather)

    } catch FetchKeyError.networkUnavailable {
        // No cached key and offline
        showError(
            title: "No Connection",
            message: "Please connect to the internet to continue."
        )

    } catch FetchKeyError.recordNotFound {
        // Development/configuration error
        #if DEBUG
        assertionFailure("API key not found - check CloudKit configuration")
        #endif
        showError(
            title: "Configuration Error",
            message: "Please contact support."
        )

    } catch FetchKeyError.cloudKitRestricted {
        // iCloud disabled
        showError(
            title: "iCloud Required",
            message: "This app requires iCloud to be enabled in Settings.",
            actions: [
                .init(title: "Open Settings", action: openSettings),
                .init(title: "Cancel", style: .cancel)
            ]
        )

    } catch FetchKeyError.missingField(let field) {
        // Schema error
        logger.error("CloudKit schema error: missing field '\(field)'")
        showError(
            title: "Configuration Error",
            message: "Please contact support."
        )

    } catch FetchKeyError.cloudKitError(let error) {
        // Other CloudKit errors
        logger.error("CloudKit error: \(error.localizedDescription)")
        showError(
            title: "Service Unavailable",
            message: "Please try again later."
        )

    } catch {
        // Unexpected errors
        logger.error("Unexpected error: \(error)")
        showError(
            title: "Error",
            message: "An unexpected error occurred."
        )
    }
}
```

## Best Practices

### Use Specific Error Handling

Match on specific ``FetchKeyError`` cases instead of catching all errors:

```swift
// Good
catch FetchKeyError.networkUnavailable {
    showOfflineUI()
}

// Avoid
catch {
    // Too broad - can't provide specific user guidance
}
```

### Log Errors Appropriately

Include enough detail for debugging while respecting user privacy:

```swift
catch FetchKeyError.cloudKitError(let error) {
    // Include underlying error for diagnostics
    logger.error("Failed to fetch key: \(error.localizedDescription)")
}
```

### Trust the Fallback Mechanism

Don't manually implement fallback logic — the library handles it:

```swift
// No need for this
var apiKey: APIKey?
do {
    apiKey = try await reader.apiKey(named: .weather, expiresMinutes: 60)
} catch {
    // Don't manually check for cached keys
    apiKey = cachedKeyFromSomewhere  // ❌ Unnecessary
}

// The library already does this
let apiKey = try await reader.apiKey(named: .weather, expiresMinutes: 60)
// ✅ Automatically uses cache if fetch fails
```

### Handle Development Errors Differently

Use assertions for configuration errors that should only occur during development:

```swift
catch FetchKeyError.recordNotFound {
    #if DEBUG
    assertionFailure("Key not found - check CloudKit setup")
    #endif

    // Still show user-friendly message in production
    showConfigurationError()
}
```

## See Also

- ``FetchKeyError``
- ``APIKeyReader/apiKey(named:expiresMinutes:)``
- <doc:CacheStrategy>
