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
    let expiresMinutes: Int
    
    init(key: String,
         expiresMinutes: Int) {
        self.key = key
        self.expiresMinutes = expiresMinutes
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
        return minutes >= expiresMinutes
    }
}
