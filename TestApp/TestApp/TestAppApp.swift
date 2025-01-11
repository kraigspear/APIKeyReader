//
//  TestAppApp.swift
//  TestApp
//
//  Created by Kraig Spear on 1/10/25.
//

import APIKeyReader
import os
import SwiftUI

let logger = os.Logger(subsystem: "com.spearware.APITest", category: "main")

@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any]
    ) async -> UIBackgroundFetchResult {
        guard let keyRefreshInfo = KeyRefreshInfo(userInfo: userInfo) else {
            return .noData
        }
        do {
            logger.debug("Attempt to refresh key")
            try await APIKeyReader.shared.refreshKey(keyRefreshInfo)
            logger.info("New Key refreshed")
            return .newData
        } catch {
            logger.error("Failed to refresh key")
            return .failed
        }
    }
}

@main
struct TestAppApp: App {
    init() {
        _ = APIKeyReader.configure(apiKeyCloudKit: .init(containerIdentifier: "iCloud.com.spearware.Klimate"))
    }
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
