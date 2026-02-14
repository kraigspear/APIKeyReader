# Getting Started with APIKeyReader

Learn how to integrate APIKeyReader into your project and fetch your first API key.

## Overview

APIKeyReader helps you securely manage API keys by storing them in CloudKit and caching them locally. This guide walks you through setup, configuration, and basic usage.

## Add the Package Dependency

Add APIKeyReader to your project using Swift Package Manager.

### Xcode

1. In Xcode, select **File → Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/kraigspear/APIKeyReader`
3. Select the version requirement and click **Add Package**

### Package.swift

Add to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/kraigspear/APIKeyReader", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["APIKeyReader"]
)
```

## Configure CloudKit

APIKeyReader fetches keys from CloudKit. You need to set up a CloudKit container and configure your app.

### 1. Enable iCloud Capability

In your app target's **Signing & Capabilities** tab:
1. Click **+ Capability**
2. Add **iCloud**
3. Check **CloudKit**
4. Note your container identifier (e.g., `iCloud.com.example.app`)

### 2. Create the CloudKit Schema

In CloudKit Dashboard (https://icloud.developer.apple.com):

1. Select your container
2. Go to **Schema → Record Types**
3. Create a new record type named `APIKey`
4. Add a field: `key` (type: String)

### 3. Add API Keys to CloudKit

In the CloudKit Dashboard:

1. Go to **Data → Records**
2. Create a new `APIKey` record
3. Set the **Record Name** to your key identifier (e.g., `OpenWeatherMap`)
4. Set the `key` field to your actual API key value
5. Save the record

> Important: The record name is the identifier you'll use in code, while the `key` field contains the actual secret value.

## Define Your Key Names

Create type-safe identifiers for your API keys by extending `APIKeyName`:

```swift
import APIKeyReader

extension APIKeyName {
    static let openWeatherMap = APIKeyName(rawValue: "OpenWeatherMap")
    static let mapbox = APIKeyName(rawValue: "Mapbox")
}
```

This provides compile-time validation and autocomplete support.

## Initialize APIKeyReader

Create an instance with your CloudKit container identifier:

```swift
import APIKeyReader

let apiKeyReader = APIKeyReader(
    containerIdentifier: "iCloud.com.example.app"
)
```

> Tip: The container identifier must match the one configured in your app's iCloud capabilities.

## Fetch Your First Key

Use the `apiKey(named:expiresMinutes:)` method to retrieve a key:

```swift
do {
    let apiKey = try await apiKeyReader.apiKey(
        named: .openWeatherMap,
        expiresMinutes: 60
    )

    // Use the key's raw value with your API
    let weather = try await fetchWeather(apiKey: apiKey.rawValue)
} catch {
    print("Failed to fetch API key: \(error)")
}
```

The `expiresMinutes` parameter controls how long the key is cached locally before being refreshed from CloudKit.

### How It Works

1. **Check cache** — First looks in the Keychain for a valid cached key
2. **Fetch if needed** — If expired or missing, fetches from CloudKit
3. **Cache locally** — Stores the key in the Keychain with the specified expiration
4. **Fallback** — Returns expired cached key if CloudKit is unavailable

## Complete Example

Here's a complete example of fetching weather data using an API key:

```swift
import APIKeyReader
import Foundation

// Define your key names
extension APIKeyName {
    static let openWeatherMap = APIKeyName(rawValue: "OpenWeatherMap")
}

// Create the reader
let apiKeyReader = APIKeyReader(
    containerIdentifier: "iCloud.com.example.app"
)

// Fetch and use the key
Task {
    do {
        // Get the API key (cached for 1 hour)
        let apiKey = try await apiKeyReader.apiKey(
            named: .openWeatherMap,
            expiresMinutes: 60
        )

        // Build your API request
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "London"),
            URLQueryItem(name: "appid", value: apiKey.rawValue)
        ]

        // Make the request
        let (data, _) = try await URLSession.shared.data(from: components.url!)

        // Process the response
        print("Weather data received: \(data.count) bytes")

    } catch let error as FetchKeyError {
        switch error {
        case .networkUnavailable:
            print("Network unavailable - check connection")
        case .recordNotFound:
            print("API key not found in CloudKit")
        case .cloudKitRestricted:
            print("iCloud access is restricted on this device")
        default:
            print("Error fetching key: \(error.localizedDescription)")
        }
    } catch {
        print("Unexpected error: \(error)")
    }
}
```

## Next Steps

Now that you have basic integration working, explore these topics:

- <doc:ErrorHandling> — Learn how to handle different error scenarios
- <doc:CacheStrategy> — Understand caching behavior and expiration
- <doc:SwiftUIIntegration> — Use APIKeyReader with SwiftUI views
- ``APIKeyReader/clearCache(for:)`` — Clear cached keys when needed
