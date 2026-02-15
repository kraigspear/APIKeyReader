import APIKeyReader
import SwiftUI

private let testKeyName = APIKeyName(rawValue: "rainviewer")

struct ContentView: View {
    @State private var testResult: String?
    @Environment(APIKeyReader.self) var apiKeyReader

    var body: some View {
        List {
            TestSection("Test") {
                AsyncTestButton(
                    title: "Test Fetch Key",
                    accessibilityLabel: "Fetch test",
                    accessibilityIdentifier: "testFetchKey",
                    testResult: $testResult,
                ) {
                    let key = try await apiKeyReader.apiKey(
                        named: testKeyName,
                        expiresMinutes: 1,
                    )
                    return "Key fetched successfully"
                }

                AsyncTestButton(
                    title: "Test multiple calls",
                    accessibilityLabel: "Concurrent fetch test",
                    accessibilityIdentifier: "testMultipleCalls",
                    testResult: $testResult,
                ) {
                    try await withThrowingTaskGroup(of: APIKey.self) { group in
                        for _ in 0 ..< 10 {
                            group.addTask {
                                try await apiKeyReader.apiKey(
                                    named: testKeyName,
                                    expiresMinutes: 1,
                                )
                            }
                        }

                        var results: [APIKey] = []

                        for try await result in group {
                            results.append(result)
                        }

                        if results.first != nil {
                            return "All \(results.count) fetches succeeded"
                        }
                        return "No results"
                    }
                }

                AsyncTestButton(
                    title: "Missing key",
                    accessibilityLabel: "Missing key test",
                    accessibilityIdentifier: "testMissingKey",
                    testResult: $testResult,
                    errorDescription: { error in
                        error.localizedDescription
                    },
                    action: {
                        let key = try await apiKeyReader.apiKey(
                            named: .init(rawValue: "missingKey"),
                            expiresMinutes: 1,
                        )
                        return "Key fetched successfully"
                    },
                )
            }

            TestSection("Cache") {
                AsyncTestButton(
                    title: "Verify cached key",
                    accessibilityLabel: "Cached key verification",
                    accessibilityIdentifier: "verifyCachedKey",
                    testResult: $testResult,
                    errorDescription: { error in
                        error.localizedDescription
                    },
                    action: {
                        await apiKeyReader.clearCache(for: testKeyName)
                        // Fetch from CloudKit and cache in Keychain
                        let key = try await apiKeyReader.apiKey(
                            named: testKeyName,
                            expiresMinutes: 1,
                        )
                        // Read back from Keychain cache
                        let cachedKey = try await apiKeyReader.apiKey(
                            named: testKeyName,
                            expiresMinutes: 1,
                        )
                        return key.rawValue == cachedKey.rawValue
                            ? "Cached key verified"
                            : "Mismatch: keys differ"
                    },
                )

                AsyncTestButton(
                    title: "Clear cached key",
                    accessibilityLabel: "Cache clear",
                    accessibilityIdentifier: "clearCachedKey",
                    testResult: $testResult,
                ) {
                    await apiKeyReader.clearCache(for: testKeyName)
                    return "Cache cleared"
                }
            }

            TestSection("Expired-Key Fallback") {
                VStack(alignment: .leading) {
                    SecondaryCaptionText("1. Tap 'Cache key' to fetch and cache")
                    SecondaryCaptionText("2. Wait 1 minute for expiration")
                    SecondaryCaptionText("3. Enable airplane mode")
                    SecondaryCaptionText("4. Tap 'Fetch expired' — should return stale key")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Fallback instructions: tap cache key, wait one minute for expiration, enable airplane mode, then tap fetch expired.",
                )

                AsyncTestButton(
                    title: "Cache key (1 min expiry)",
                    accessibilityLabel: "One minute cache",
                    accessibilityIdentifier: "cacheKeyForExpiry",
                    testResult: $testResult,
                ) {
                    let key = try await apiKeyReader.apiKey(
                        named: testKeyName,
                        expiresMinutes: 1,
                    )
                    return "Key cached successfully"
                }

                AsyncTestButton(
                    title: "Fetch expired (airplane mode)",
                    accessibilityLabel: "Expired fallback",
                    accessibilityIdentifier: "fetchExpired",
                    testResult: $testResult,
                ) {
                    let key = try await apiKeyReader.apiKey(
                        named: testKeyName,
                        expiresMinutes: 1,
                    )
                    return "Fallback worked"
                }
            }

            TestSection("Error Types") {
                AsyncTestButton(
                    title: "Fetch — shows error type",
                    accessibilityLabel: "Error type check",
                    accessibilityIdentifier: "fetchShowsErrorType",
                    testResult: $testResult,
                ) {
                    let key = try await apiKeyReader.apiKey(
                        named: testKeyName,
                        expiresMinutes: 1,
                    )
                    return "OK"
                }
            }

            TestSection("Result") {
                Text("Test Result: \(testResult ?? "Empty")")
                    .accessibilityIdentifier("testResultText")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Test result")
                    .accessibilityValue(testResult ?? "Empty")
            }
        }
    }
}

// MARK: - Supporting Views

private struct TestSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            Text(title)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// cleanup-review: task(id:) pattern is correct for test app buttons — each tap toggles isExecuting
// which restarts the task. No production code uses this pattern; it's test-app-only UI.
private struct AsyncTestButton: View {
    let title: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    @Binding var testResult: String?
    let action: () async throws -> String
    let errorDescription: (any Error) -> String
    @State private var isExecuting = false

    init(
        title: String,
        accessibilityLabel: String? = nil,
        accessibilityIdentifier: String,
        testResult: Binding<String?>,
        errorDescription: @escaping (any Error) -> String = describeError,
        action: @escaping () async throws -> String,
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel ?? title
        self.accessibilityIdentifier = accessibilityIdentifier
        _testResult = testResult
        self.action = action
        self.errorDescription = errorDescription
    }

    var body: some View {
        Button(title) {
            isExecuting = true
        }
        .task(id: isExecuting) {
            guard isExecuting else { return }
            defer { isExecuting = false }

            do {
                let result = try await action()
                testResult = result
            } catch {
                let message = errorDescription(error)
                testResult = message
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SecondaryCaptionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Private Helpers

private func describeError(_ error: any Error) -> String {
    guard let fetchError = error as? FetchKeyError else {
        return "Unexpected: \(type(of: error)) — \(error.localizedDescription)"
    }
    switch fetchError {
    case .networkUnavailable:
        return "[networkUnavailable] \(fetchError.localizedDescription)"
    case .cloudKitRestricted:
        return "[cloudKitRestricted] \(fetchError.localizedDescription)"
    case .recordNotFound:
        return "[recordNotFound] \(fetchError.localizedDescription)"
    case let .missingField(name):
        return "[missingField: \(name)] \(fetchError.localizedDescription)"
    case .cloudKitError:
        return "[cloudKitError] \(fetchError.localizedDescription)"
    }
}

// MARK: - Previews

#Preview {
    ContentView()
}
