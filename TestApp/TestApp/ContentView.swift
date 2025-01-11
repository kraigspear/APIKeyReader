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
        VStack {
            Button(
                action: {
                    Task {
                        do {
                            apiKey = try await APIKeyReader.shared.apiKey(named: .rainviewer)
                        } catch {
                            apiKey = error.localizedDescription
                        }
                    }
                },
                label: { Text("Read Key") }
            )
            Text("APIKey: \(apiKey)")
        }
    }
}

#Preview {
    ContentView()
}
