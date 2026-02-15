import Foundation
import Testing
@testable import APIKeyReader

@Suite("SavedAPIKey")
struct SavedAPIKeyTests {
    @Test("is not expired when elapsed time is below the threshold")
    func notExpiredWhenBelowThreshold() throws {
        // Given
        let expiresMinutes = 10
        let updated = Date().addingTimeInterval(-599)
        let savedKey = try makeSavedAPIKey(
            updated: updated,
            expiresMinutes: expiresMinutes,
        )

        // When
        let expired = savedKey.expired

        // Then
        #expect(expired == false)
    }

    @Test("is expired when elapsed time is exactly the threshold")
    func expiredAtThreshold() throws {
        // Given
        let expiresMinutes = 10
        let updated = Date().addingTimeInterval(-600)
        let savedKey = try makeSavedAPIKey(
            updated: updated,
            expiresMinutes: expiresMinutes,
        )

        // When
        let expired = savedKey.expired

        // Then
        #expect(expired)
    }

    @Test("is expired when elapsed time is above the threshold")
    func expiredAboveThreshold() throws {
        // Given
        let expiresMinutes = 10
        let updated = Date().addingTimeInterval(-660)
        let savedKey = try makeSavedAPIKey(
            updated: updated,
            expiresMinutes: expiresMinutes,
        )

        // When
        let expired = savedKey.expired

        // Then
        #expect(expired)
    }

    @Test("is not expired when updated timestamp is in the future")
    func notExpiredWhenTimestampIsInTheFuture() throws {
        // Given
        let expiresMinutes = 10
        let updated = Date().addingTimeInterval(60)
        let savedKey = try makeSavedAPIKey(
            updated: updated,
            expiresMinutes: expiresMinutes,
        )

        // When
        let expired = savedKey.expired

        // Then
        #expect(expired == false)
    }

    private func makeSavedAPIKey(
        updated: Date,
        expiresMinutes: Int,
    ) throws -> SavedAPIKey {
        struct Payload: Codable {
            let key: APIKey
            let updated: Date
            let expiresMinutes: Int
        }

        let payload = Payload(
            key: APIKey(rawValue: "test-key"),
            updated: updated,
            expiresMinutes: expiresMinutes,
        )
        let data = try JSONEncoder().encode(payload)
        return try SavedAPIKey.decode(data)
    }
}
