# APIKeyReader

A Swift library for securely managing API keys using CloudKit, with intelligent caching and error handling.

## Features

- **CloudKit Integration**: Securely store API keys in CloudKit's public database
- **Local Caching**: Cache keys locally with configurable expiration times
- **Thread-Safe**: Actor-based implementation ensures thread-safe access
- **Concurrent Request Coalescing**: Multiple requests for the same key result in a single CloudKit fetch
- **Graceful Degradation**: Falls back to expired keys when network is unavailable
- **Type Safety**: Strongly-typed API with compile-time key validation
- **Zero Dependencies**: Uses only Apple frameworks

## Requirements

- iOS 18.0+
- macOS 15.0+
- Swift 6.0+
- Xcode 16.0+

## Installation

### Swift Package Manager

Add APIKeyReader to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/kraigspear/APIKeyReader.git", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Choose version requirements
4. Add to your target

## Setup

### 1. CloudKit Configuration

1. Enable CloudKit capability in your app
2. Create a CloudKit container (e.g., `iCloud.com.yourcompany.yourapp`)
3. In CloudKit Dashboard, create a record type named `Keys` with fields:
   - `name` (String) - The API key identifier
   - `key` (String) - The actual API key value

### 2. Add Keys to CloudKit

In CloudKit Dashboard:
1. Navigate to your container's public database
2. Create new records of type `Keys`
3. Set the `name` field (e.g., "openWeatherMap")
4. Set the `key` field to your actual API key

### 3. Initialize APIKeyReader

```swift
import APIKeyReader
import SwiftUI

@main
struct MyApp: App {
    @State private var apiKeyReader: APIKeyReader
    
    init() {
        _apiKeyReader = State(
            initialValue: APIKeyReader(containerIdentifier: "iCloud.com.yourcompany.yourapp")
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiKeyReader)
        }
    }
}
```

## Usage

### Define Your API Keys

```swift
import APIKeyReader

extension APIKeyName {
    static let openWeatherMap = Self(rawValue: "openWeatherMap")
    static let googleMaps = Self(rawValue: "googleMaps")
}
```

### Fetch API Keys

```swift
struct ContentView: View {
    @Environment(APIKeyReader.self) private var apiKeyReader
    
    func fetchWeatherData() async {
        do {
            let apiKey = try await apiKeyReader.apiKey(
                named: .openWeatherMap,
                expiresMinutes: 60  // Cache for 60 minutes
            )
            
            // Use the key
            let url = URL(string: "https://api.openweathermap.org/data?appid=\(apiKey.rawValue)")!
        } catch {
            print("Error fetching API key: \(error)")
        }
    }
}
```

### Error Handling

```swift
@Environment(APIKeyReader.self) private var apiKeyReader

func loadAPIKey() async {
    do {
        let apiKey = try await apiKeyReader.apiKey(
            named: .myAPIKey,
            expiresMinutes: 30
        )
    } catch FetchKeyError.networkUnavailable {
        // Handle offline scenario
        print("Network unavailable, using cached key if available")
    } catch FetchKeyError.recordNotFound {
        // Key doesn't exist in CloudKit
        print("API key not found in CloudKit")
    } catch {
        // Handle other errors
        print("Error: \(error)")
    }
}
```

## How It Works

1. When you request an API key, APIKeyReader first checks the local cache
2. If the cached key is still valid (not expired), it's returned immediately
3. If the key is expired or not cached, a fetch from CloudKit is initiated
4. Multiple concurrent requests for the same key are coalesced into a single fetch
5. If the network is unavailable, expired cached keys are returned as a fallback
6. Successfully fetched keys are cached with the specified expiration time

## Best Practices

- Set appropriate expiration times based on your key rotation policy
- Handle errors gracefully, especially `networkUnavailable`
- Define all your API key names in a single extension for easy management
- Consider longer expiration times for keys that rarely change

## License

[Add your license here]

## Contributing

[Add contributing guidelines if applicable]