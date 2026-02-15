import CloudKit
import Foundation
import Testing
@testable import APIKeyReader

@Suite("CloudKitKeyProvider")
struct CloudKitKeyProviderTests {
    @Test("maps restricted account status to cloudKitRestricted")
    func accountRestrictedMapsToCloudKitRestricted() async {
        let provider = CloudKitKeyProvider(
            accountStatusProvider: { .restricted },
            queryProvider: { _ in
                nil
            },
        )

        await #expect {
            _ = try await provider.fetchAPIKey(APIKeyName(rawValue: "test"))
        } throws: { error in
            guard let fetchError = error as? FetchKeyError else {
                return false
            }
            if case .cloudKitRestricted = fetchError {
                return true
            }
            return false
        }
    }

    @Test("maps no-match to recordNotFound")
    func noMatchMapsToRecordNotFound() async {
        let provider = CloudKitKeyProvider(
            accountStatusProvider: { .available },
            queryProvider: { _ in nil },
        )

        let keyName = APIKeyName(rawValue: "missing-key")

        await #expect {
            _ = try await provider.fetchAPIKey(keyName)
        } throws: { error in
            guard let fetchError = error as? FetchKeyError else {
                return false
            }
            if case .recordNotFound = fetchError {
                return true
            }
            return false
        }
    }

    @Test("returns missingField when record key is absent")
    func missingFieldWhenKeyIsMissing() async {
        let queryRecord = CKRecord(recordType: "Keys")
        queryRecord["name"] = "missing-field"

        let provider = CloudKitKeyProvider(
            accountStatusProvider: { .available },
            queryProvider: { _ in
                .success(queryRecord)
            },
        )

        let keyName = APIKeyName(rawValue: "missing-field")
        await #expect {
            _ = try await provider.fetchAPIKey(keyName)
        } throws: { error in
            guard let fetchError = error as? FetchKeyError else {
                return false
            }
            if case .missingField = fetchError {
                return true
            }
            return false
        }
    }

    @Test("returns key when record contains valid key field")
    func returnsKeyFromValidRecord() async throws {
        let queryRecord = CKRecord(recordType: "Keys")
        queryRecord["name"] = "valid-key"
        queryRecord["key"] = "key-value"

        let provider = CloudKitKeyProvider(
            accountStatusProvider: { .available },
            queryProvider: { _ in
                .success(queryRecord)
            },
        )

        let result = try await provider.fetchAPIKey(APIKeyName(rawValue: "valid-key"))
        #expect(result.rawValue == "key-value")
    }
}
