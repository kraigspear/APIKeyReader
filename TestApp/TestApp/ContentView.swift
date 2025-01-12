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
    
    var body: some View {
        List {
            Button("Test Fetch Key") {
                Task {
                    do {
                        apiKey = try await APIKeyReader.shared.apiKey(named: .rainviewer)
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
                                let key = try await apiKeyReader.apiKey(named: .rainviewer)
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
            Button("Remove key from Defaults") {
                UserDefaults.standard.removeObject(forKey: "rainviewer")
            }
        }
        Text("APIKey: \(apiKey)")
    }
}

#Preview {
    ContentView()
}
