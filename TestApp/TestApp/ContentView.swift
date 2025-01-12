//
//  ContentView.swift
//  TestApp
//
//  Created by Kraig Spear on 1/10/25.
//

import APIKeyReader
import SwiftUI
import SwiftData

struct ContentView: View {
    
    @State private var apiKey = "Empty"
    private let keyName = "rainviewer"
    
    var body: some View {
        List {
            Section ("Test") {
                Button("Test Fetch Key") {
                    Task {
                        do {
                            apiKey = try await APIKeyReader.shared.apiKey(
                                named: keyName,
                                expiresMinutes: 1
                            )
                        } catch {
                            apiKey = error.localizedDescription
                        }
                    }
                }
                Button("Test multiple calls") {
                    Task {
                        let apiKeyReader = APIKeyReader.shared
                        
                        try await withThrowingTaskGroup(of: String.self) { group in
                            for _ in 0..<10 {
                                group.addTask {
                                    let key = try await apiKeyReader.apiKey(
                                        named: keyName,
                                        expiresMinutes: 1
                                    )
                                    return key
                                }
                            }
                            
                            var results: [String] = []
                            
                            for try await result in group {
                                results.append(result)
                            }
                            
                            apiKey = results.first!
                        }
                    }
                }
                Button("Key does't exist") {
                    Task {
                        do {
                            apiKey = try await APIKeyReader.shared.apiKey(
                                named: "missingKey",
                                expiresMinutes: 1
                            )
                        } catch {
                            apiKey = error.localizedDescription
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
                Text("APIKey: \(apiKey)")
            }
        }
    }
}

#Preview {
    ContentView()
}
