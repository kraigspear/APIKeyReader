//
//  TestAppApp.swift
//  TestApp
//
//  Created by Kraig Spear on 1/10/25.
//

import APIKeyReader
import os
import SwiftUI

@main
struct TestAppApp: App {
    
    @State private var apiKeyReader: APIKeyReader
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiKeyReader)
        }
    }
    
    init() {
        _apiKeyReader = State(
            initialValue: .init(
                containerIdentifier:  "iCloud.com.spearware.Klimate"
            )
        )
    }
}
