import APIKeyReader
import SwiftUI

struct ContentView: View {
    @State private var testResult = "Empty"
    @Environment(APIKeyReader.self) var apiKeyReader
    private let keyName = APIKeyName(rawValue: "rainviewer")

    var body: some View {
        List {
            Section("Test") {
                Button("Test Fetch Key") {
                    Task {
                        do {
                            testResult = try await apiKeyReader.apiKey(
                                named: keyName,
                                expiresMinutes: 1,
                            ).rawValue
                        } catch {
                            testResult = error.localizedDescription
                        }
                    }
                }
                Button("Test multiple calls") {
                    Task {
                        let apiKeyReader = apiKeyReader

                        try await withThrowingTaskGroup(of: APIKey.self) { group in
                            for _ in 0 ..< 10 {
                                group.addTask {
                                    let key = try await apiKeyReader.apiKey(
                                        named: keyName,
                                        expiresMinutes: 1,
                                    )
                                    return key
                                }
                            }

                            var results: [APIKey] = []

                            for try await result in group {
                                results.append(result)
                            }

                            testResult = results.first!.rawValue
                        }
                    }
                }
                Button("Key does't exist") {
                    Task {
                        do {
                            testResult = try await apiKeyReader.apiKey(
                                named: .init(rawValue: "missingKey"),
                                expiresMinutes: 1,
                            ).rawValue
                        } catch {
                            testResult = error.localizedDescription
                        }
                    }
                }
            }

            Section("Cache") {
                Button("Verify cached key") {
                    Task {
                        await apiKeyReader.clearCache(for: keyName)
                        do {
                            // Fetch from CloudKit and cache in Keychain
                            let key = try await apiKeyReader.apiKey(
                                named: keyName,
                                expiresMinutes: 1,
                            )
                            // Read back from Keychain cache
                            let cachedKey = try await apiKeyReader.apiKey(
                                named: keyName,
                                expiresMinutes: 1,
                            )
                            testResult = key.rawValue == cachedKey.rawValue
                                ? "Cached: \(cachedKey.rawValue)"
                                : "Mismatch: \(key.rawValue) vs \(cachedKey.rawValue)"
                        } catch {
                            testResult = error.localizedDescription
                        }
                    }
                }
                Button("Clear cached key") {
                    Task {
                        await apiKeyReader.clearCache(for: keyName)
                        testResult = "Cache cleared"
                    }
                }
            }
            Section("Result") {
                Text("Test Result: \(testResult)")
            }
        }
    }
}

#Preview {
    ContentView()
}
