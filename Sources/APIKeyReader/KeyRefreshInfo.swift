//
//  KeyRefreshInfo.swift
//  APIKeyReader
//
//  Created by Kraig Spear on 1/11/25.
//

import Foundation
import CloudKit

public struct KeyRefreshInfo: Sendable {
    let recordID: CKRecord.ID
    
    public init?(userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.notificationType == .query,
              let queryNotification = notification as? CKQueryNotification,
              let recordID = queryNotification.recordID else {
            return nil
        }
        self.recordID = recordID
    }
    
}
