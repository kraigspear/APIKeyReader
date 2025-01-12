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
    init() {
        APIKeyReader.configure(
            apiKeyCloudKit:
                    .init(
                        containerIdentifier: "iCloud.com.spearware.Klimate"
                    )
        )
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
