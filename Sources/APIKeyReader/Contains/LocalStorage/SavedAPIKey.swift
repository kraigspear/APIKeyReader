import Foundation
import SpearFoundation

struct SavedAPIKey: Codable {
    let key: APIKey
    let updated: Date
    let expiresMinutes: Int

    init(
        key: APIKey,
        expiresMinutes: Int,
    ) {
        self.key = key
        self.expiresMinutes = expiresMinutes
        updated = Date()
    }

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> SavedAPIKey {
        try JSONDecoder().decode(SavedAPIKey.self, from: data)
    }

    var expired: Bool {
        updated.numberOfMinutesBetween() >= expiresMinutes
    }
}
