//
//  KeyRefreshInfo.swift
//  APIKeyReader
//
//  Created by Kraig Spear on 1/11/25.
//

import Foundation
import CloudKit

struct SavedAPIKey: Codable {
    let key: String
    let updated: Date
    
    init(key: String) {
        self.key = key
        self.updated = Date()
    }
    
    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    static func decode(_ data: Data) throws -> SavedAPIKey {
        try JSONDecoder().decode(SavedAPIKey.self, from: data)
    }
    
    var expired: Bool {
        let minutes = Calendar.current.dateComponents(
            [.minute],
            from: updated,
            to: Date()
        ).minute ?? 0
        #if DEBUG
            let expiredMinutes = 1
        #else
            let expiredMinutes = 60
        #endif
        return minutes >= expiredMinutes
    }
}
