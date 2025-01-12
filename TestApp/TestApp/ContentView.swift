//
//  ContentView.swift
//  TestApp
//
//  Created by Kraig Spear on 1/10/25.
//

import APIKeyReader
import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var testResult = "Empty"
    private let keyName = APIKeyName(rawValue: "rainviewer")

    var body: some View {
        List {
            Section("Test") {
                Button("Test Fetch Key") {
                    Task {
                        do {
                            testResult = try await APIKeyReader.shared.apiKey(
                                named: keyName,
                                expiresMinutes: 1
                            ).rawValue
                        } catch {
                            testResult = error.localizedDescription
                        }
                    }
                }
                Button("Test multiple calls") {
                    Task {
                        let apiKeyReader = APIKeyReader.shared

                        try await withThrowingTaskGroup(of: APIKey.self) { group in
                            for _ in 0 ..< 10 {
                                group.addTask {
                                    let key = try await apiKeyReader.apiKey(
                                        named: keyName,
                                        expiresMinutes: 1
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
                            testResult = try await APIKeyReader.shared.apiKey(
                                named: .init(rawValue: "missingKey"),
                                expiresMinutes: 1
                            ).rawValue
                        } catch {
                            testResult = error.localizedDescription
                        }
                    }
                }
            }

            Section("Setup") {
                Button("Remove key from Defaults") {
                    UserDefaults.standard.removeObject(forKey: "rainviewer")
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
