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
        let account = "com.spearware.APIKeyReader.Keychain.tests.\(UUID().uuidString)"
        try await withBackend { _ in
            let loaded = try KeychainStorage.load(account: account)
            #expect(loaded == nil)
        }
    }

    @Test("saves and loads bytes")
    func savesAndLoadsValue() async throws {
        let account = "com.spearware.APIKeyReader.Keychain.tests.\(UUID().uuidString)"
        try await withBackend { _ in
            let value = "key-value".data(using: .utf8)!
            #expect(KeychainStorage.save(data: value, account: account))
            let loaded = try KeychainStorage.load(account: account)
            #expect(loaded == value)
        }
    }

    @Test("updates existing value")
    func updatesExistingValue() async throws {
        let account = "com.spearware.APIKeyReader.Keychain.tests.\(UUID().uuidString)"
        try await withBackend { _ in
            let firstValue = "first".data(using: .utf8)!
            let secondValue = "second".data(using: .utf8)!
            #expect(KeychainStorage.save(data: firstValue, account: account))
            #expect(KeychainStorage.save(data: secondValue, account: account))
            let loaded = try KeychainStorage.load(account: account)
            #expect(loaded == secondValue)
        }
    }

    @Test("clears stored value")
    func clearsValue() async throws {
        let account = "com.spearware.APIKeyReader.Keychain.tests.\(UUID().uuidString)"
        try await withBackend { _ in
            _ = KeychainStorage.save(data: "to-clear".data(using: .utf8)!, account: account)
            KeychainStorage.clear(account: account)
            let loaded = try KeychainStorage.load(account: account)
            #expect(loaded == nil)
        }
    }

    @Test("preserves only access control when both access attributes exist")
    func preservesOnlyAccessControlWhenBothExist() {
        var accessControlError: Unmanaged<CFError>?
        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [],
            &accessControlError,
        )
        #expect(accessControl != nil)
        guard let accessControl else { return }

        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrAccessControl as String: accessControl,
        ]

        let preserved = KeychainStorage.preservedAccessAttributes(from: attributes)
        #expect(preserved.count == 1)
        #expect(preserved[kSecAttrAccessControl as String] != nil)
        #expect(preserved[kSecAttrAccessible as String] == nil)
    }

    @Test("preserves accessibility when access control is absent")
    func preservesAccessibilityWhenAccessControlIsAbsent() {
        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: accessible,
        ]

        let preserved = KeychainStorage.preservedAccessAttributes(from: attributes)
        #expect(preserved.count == 1)
        #expect((preserved[kSecAttrAccessible as String] as? String) == (accessible as String))
        #expect(preserved[kSecAttrAccessControl as String] == nil)
    }
}
