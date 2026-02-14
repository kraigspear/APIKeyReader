# SwiftUI Integration

Learn how to use APIKeyReader effectively in SwiftUI views and apps.

## Overview

APIKeyReader's actor-based design integrates seamlessly with SwiftUI's async task lifecycle and environment system. This guide shows common patterns for managing API keys in SwiftUI applications.

## Basic View Integration

The simplest integration uses SwiftUI's `.task` modifier to fetch keys when a view appears:

```swift
import SwiftUI
import APIKeyReader

struct WeatherView: View {
    @State private var apiKeyReader = APIKeyReader(
        containerIdentifier: "iCloud.com.example.app"
    )
    @State private var weatherData: WeatherData?
    @State private var error: Error?

    var body: some View {
        Group {
            if let data = weatherData {
                WeatherContent(data: data)
            } else if error != nil {
                ErrorView(error: error)
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            await loadWeather()
        }
    }

    private func loadWeather() async {
        do {
            let apiKey = try await apiKeyReader.apiKey(
                named: .openWeatherMap,
                expiresMinutes: 60
            )

            weatherData = try await fetchWeather(using: apiKey.rawValue)
        } catch {
            self.error = error
        }
    }
}
```

## Environment-Based Sharing

Share a single ``APIKeyReader`` instance across your app using SwiftUI's environment system.

### 1. Define the Environment Key

```swift
import SwiftUI
import APIKeyReader

private struct APIKeyReaderKey: EnvironmentKey {
    static let defaultValue = APIKeyReader(
        containerIdentifier: "iCloud.com.example.app"
    )
}

extension EnvironmentValues {
    var apiKeyReader: APIKeyReader {
        get { self[APIKeyReaderKey.self] }
        set { self[APIKeyReaderKey.self] = newValue }
    }
}
```

### 2. Provide at App Root

```swift
@main
struct MyApp: App {
    @State private var apiKeyReader = APIKeyReader(
        containerIdentifier: "iCloud.com.example.app"
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.apiKeyReader, apiKeyReader)
        }
    }
}
```

### 3. Access in Views

```swift
struct WeatherView: View {
    @Environment(\.apiKeyReader) private var apiKeyReader

    var body: some View {
        WeatherContent()
            .task {
                let key = try? await apiKeyReader.apiKey(
                    named: .openWeatherMap,
                    expiresMinutes: 60
                )
                // Use key
            }
    }
}
```

## ViewModel Pattern

For complex views, encapsulate key fetching in an observable view model:

```swift
import SwiftUI
import APIKeyReader

@Observable
final class WeatherViewModel {
    private let apiKeyReader: APIKeyReader

    var weatherData: WeatherData?
    var isLoading = false
    var error: Error?

    init(apiKeyReader: APIKeyReader) {
        self.apiKeyReader = apiKeyReader
    }

    func loadWeather(for city: String) async {
        isLoading = true
        error = nil

        do {
            let apiKey = try await apiKeyReader.apiKey(
                named: .openWeatherMap,
                expiresMinutes: 60
            )

            weatherData = try await WeatherService.fetch(
                city: city,
                apiKey: apiKey.rawValue
            )
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func refresh() async {
        await loadWeather(for: "London")
    }
}

struct WeatherView: View {
    @Environment(\.apiKeyReader) private var apiKeyReader
    @State private var viewModel: WeatherViewModel?

    var body: some View {
        Group {
            if let model = viewModel {
                if model.isLoading {
                    ProgressView()
                } else if let data = model.weatherData {
                    WeatherContent(data: data)
                } else if let error = model.error {
                    ErrorView(error: error)
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = WeatherViewModel(apiKeyReader: apiKeyReader)
                await viewModel?.loadWeather(for: "London")
            }
        }
        .refreshable {
            await viewModel?.refresh()
        }
    }
}
```

## Handling Errors in SwiftUI

Display appropriate UI based on different error types:

```swift
import SwiftUI
import APIKeyReader

struct APIKeyErrorView: View {
    let error: FetchKeyError

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let action = actionButton {
                action
            }
        }
        .padding()
    }

    private var iconName: String {
        switch error {
        case .networkUnavailable:
            "wifi.slash"
        case .cloudKitRestricted:
            "icloud.slash"
        case .recordNotFound, .missingField:
            "exclamationmark.triangle"
        case .cloudKitError:
            "exclamationmark.circle"
        }
    }

    private var title: String {
        switch error {
        case .networkUnavailable:
            "No Connection"
        case .cloudKitRestricted:
            "iCloud Required"
        case .recordNotFound, .missingField:
            "Configuration Error"
        case .cloudKitError:
            "Service Unavailable"
        }
    }

    private var message: String {
        switch error {
        case .networkUnavailable:
            "Please check your internet connection and try again."
        case .cloudKitRestricted:
            "This app requires iCloud to be enabled in Settings."
        case .recordNotFound, .missingField:
            "Please contact support for assistance."
        case .cloudKitError:
            "The service is temporarily unavailable. Please try again later."
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch error {
        case .cloudKitRestricted:
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        default:
            EmptyView()
        }
    }
}
```

## Multiple Concurrent Requests

Load multiple keys simultaneously using async let:

```swift
struct MultiServiceView: View {
    @Environment(\.apiKeyReader) private var apiKeyReader
    @State private var weatherData: WeatherData?
    @State private var mapData: MapData?

    var body: some View {
        VStack {
            if let weather = weatherData, let map = mapData {
                WeatherMapView(weather: weather, map: map)
            } else {
                ProgressView("Loading services...")
            }
        }
        .task {
            await loadAllServices()
        }
    }

    private func loadAllServices() async {
        do {
            // Fetch both keys in parallel
            async let weatherKey = apiKeyReader.apiKey(
                named: .openWeatherMap,
                expiresMinutes: 60
            )
            async let mapKey = apiKeyReader.apiKey(
                named: .mapbox,
                expiresMinutes: 120
            )

            // Wait for both to complete
            let (weather, map) = try await (weatherKey, mapKey)

            // Fetch data using both keys
            async let weatherFetch = WeatherService.fetch(using: weather.rawValue)
            async let mapFetch = MapService.fetch(using: map.rawValue)

            let (weatherResult, mapResult) = try await (weatherFetch, mapFetch)

            weatherData = weatherResult
            mapData = mapResult

        } catch {
            // Handle error
        }
    }
}
```

## Pull-to-Refresh with Cache Clearing

Implement pull-to-refresh that forces a fresh fetch:

```swift
struct RefreshableWeatherView: View {
    @Environment(\.apiKeyReader) private var apiKeyReader
    @State private var weatherData: WeatherData?

    var body: some View {
        List {
            if let data = weatherData {
                WeatherSection(data: data)
            }
        }
        .refreshable {
            await refreshWeather()
        }
    }

    private func refreshWeather() async {
        // Clear cache to force fresh fetch
        await apiKeyReader.clearCache(for: .openWeatherMap)

        do {
            let apiKey = try await apiKeyReader.apiKey(
                named: .openWeatherMap,
                expiresMinutes: 60
            )

            weatherData = try await WeatherService.fetch(using: apiKey.rawValue)
        } catch {
            // Handle error
        }
    }
}
```

## Offline State Handling

Show different UI states based on network availability:

```swift
import SwiftUI
import APIKeyReader

struct OfflineAwareView: View {
    @Environment(\.apiKeyReader) private var apiKeyReader
    @State private var weatherData: WeatherData?
    @State private var isOffline = false

    var body: some View {
        VStack {
            if isOffline {
                OfflineBanner()
            }

            if let data = weatherData {
                WeatherContent(data: data)
            } else {
                ProgressView()
            }
        }
        .task {
            await loadWeather()
        }
    }

    private func loadWeather() async {
        do {
            let apiKey = try await apiKeyReader.apiKey(
                named: .openWeatherMap,
                expiresMinutes: 60
            )

            weatherData = try await WeatherService.fetch(using: apiKey.rawValue)
            isOffline = false

        } catch FetchKeyError.networkUnavailable {
            // No cached key and offline
            isOffline = true

        } catch {
            // If we got here with a key, it might be expired but usable
            // The library would have returned it automatically
            if weatherData != nil {
                // We have data (from expired key), show offline indicator
                isOffline = true
            }
        }
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("You're offline. Showing cached data.")
        }
        .font(.caption)
        .padding(8)
        .background(.orange.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

## Testing SwiftUI Views

Use dependency injection to test views with mock key readers:

```swift
#if DEBUG
extension APIKeyReader {
    static let preview = APIKeyReader(
        containerIdentifier: "iCloud.com.example.app.preview"
    )
}
#endif

#Preview {
    WeatherView()
        .environment(\.apiKeyReader, .preview)
}
```

## Best Practices

### Use .task for Loading

Prefer `.task` over `.onAppear` for async operations:

```swift
// ✅ Good - properly handles async
.task {
    let key = try await apiKeyReader.apiKey(...)
}

// ❌ Avoid - creates unstructured task
.onAppear {
    Task {
        let key = try await apiKeyReader.apiKey(...)
    }
}
```

### Share via Environment

Create a single instance and share it:

```swift
// ✅ Single instance shared via environment
@State private var apiKeyReader = APIKeyReader(...)
ContentView()
    .environment(\.apiKeyReader, apiKeyReader)

// ❌ Multiple instances created
// Each view creates its own - no deduplication benefit
@State private var apiKeyReader = APIKeyReader(...)
```

### Handle All Error Cases

Provide specific UI for each error type:

```swift
// ✅ Specific error handling
catch let error as FetchKeyError {
    switch error {
    case .networkUnavailable:
        showOfflineUI()
    case .cloudKitRestricted:
        showCloudKitRequiredUI()
    // ...
    }
}

// ❌ Generic error handling
catch {
    showGenericError()  // User can't act on this
}
```

### Coordinate with View Lifecycle

Only fetch when needed:

```swift
// ✅ Fetch once per view lifecycle
.task {
    if weatherData == nil {
        await loadWeather()
    }
}

// ❌ Fetches every time task runs
.task {
    await loadWeather()  // May fetch unnecessarily
}
```

## See Also

- ``APIKeyReader``
- <doc:ErrorHandling>
- <doc:CacheStrategy>
- <doc:TestingStrategies>
