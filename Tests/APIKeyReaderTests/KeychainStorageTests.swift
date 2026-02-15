import Foundation
import Security
import Testing
@testable import APIKeyReader

@Suite("KeychainStorage")
struct KeychainStorageTests {
    private func withBackend<T>(
        _ operation: @escaping (InMemoryKeychainBackend) async throws -> T,
    ) async throws -> T {
        let backend = InMemoryKeychainBackend()
        return try await KeychainStorage.withTestBackend(
            load: { account in
                backend.load(account: account)
            },
            save: { data, account in
                backend.save(data: data, account: account)
            },
            clear: { account in
                backend.clear(account: account)
            },
        ) {
            try await operation(backend)
        }
    }

    @Test("returns nil when value is missing")
    func returnsNilForMissingValue() async throws {
        // Given
        let account = "com.spearware.APIKeyReader.Keychain.tests.\(UUID().uuidString)"

        // When
        try await withBackend { _ in
            let loaded = try KeychainStorage.load(account: account)

            // Then
            #expect(loaded == nil)
        }
    }

    @Test("saves and loads bytes")
    func savesAndLoadsValue() async throws {
        // Given
        let account = "com.spearware.APIKeyReader.Keychain.tests.\(UUID().uuidString)"
        try await withBackend { _ in
            // And
            let value = "key-value".data(using: .utf8)!

            // When
            #expect(KeychainStorage.save(data: value, account: account))
            let loaded = try KeychainStorage.load(account: account)

            // Then
            #expect(loaded == value)
        }
    }

    @Test("updates existing value")
    func updatesExistingValue() async throws {
        // Given
        let account = "com.spearware.APIKeyReader.Keychain.tests.\(UUID().uuidString)"
        try await withBackend { _ in
            // And
            let firstValue = "first".data(using: .utf8)!
            let secondValue = "second".data(using: .utf8)!

            // When
            #expect(KeychainStorage.save(data: firstValue, account: account))
            #expect(KeychainStorage.save(data: secondValue, account: account))
            let loaded = try KeychainStorage.load(account: account)

            // Then
            #expect(loaded == secondValue)
        }
    }

    @Test("clears stored value")
    func clearsValue() async throws {
        // Given
        let account = "com.spearware.APIKeyReader.Keychain.tests.\(UUID().uuidString)"
        try await withBackend { _ in
            // And
            _ = KeychainStorage.save(data: "to-clear".data(using: .utf8)!, account: account)

            // When
            KeychainStorage.clear(account: account)
            let loaded = try KeychainStorage.load(account: account)

            // Then
            #expect(loaded == nil)
        }
    }

    @Test("preserves only access control when both access attributes exist")
    func preservesOnlyAccessControlWhenBothExist() {
        // Given
        var accessControlError: Unmanaged<CFError>?
        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [],
            &accessControlError,
        )
        // And
        #expect(accessControl != nil)
        guard let accessControl else { return }

        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrAccessControl as String: accessControl,
        ]

        // When
        let preserved = KeychainStorage.preservedAccessAttributes(from: attributes)

        // Then
        #expect(preserved.count == 1)
        #expect(preserved[kSecAttrAccessControl as String] != nil)
        #expect(preserved[kSecAttrAccessible as String] == nil)
    }

    @Test("preserves accessibility when access control is absent")
    func preservesAccessibilityWhenAccessControlIsAbsent() {
        // Given
        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: accessible,
        ]

        // When
        let preserved = KeychainStorage.preservedAccessAttributes(from: attributes)

        // Then
        #expect(preserved.count == 1)
        #expect((preserved[kSecAttrAccessible as String] as? String) == (accessible as String))
        #expect(preserved[kSecAttrAccessControl as String] == nil)
    }
}
