import Foundation
import Synchronization

/// In-memory keychain test double used to isolate persistence behavior in tests.
///
/// `KeychainStorage` is exercised through closures injected by `withTestBackend`.
/// This backend provides deterministic storage semantics without touching the
/// system Keychain, so tests stay fast and free from device state.
/// A shared protocol is intentionally omitted because the seam is closure-based
/// (`load`, `save`, `clear`) rather than type-based polymorphism.
///
/// - SeeAlso: ``KeychainStorage`` for the production keychain implementation
///   this type substitutes during tests.
final class InMemoryKeychainBackend: Sendable {
    private let storage = Mutex([String: Data]())

    /// Returns bytes currently stored for an account.
    ///
    /// - Parameter account: The logical keychain account identifier.
    /// - Returns: Stored data when present; otherwise `nil`.
    func load(account: String) -> Data? {
        storage.withLock { $0[account] }
    }

    /// Stores bytes for an account, replacing any existing value.
    ///
    /// - Parameters:
    ///   - data: Bytes to persist in memory.
    ///   - account: The logical keychain account identifier.
    /// - Returns: `true` to mirror the production save API contract.
    func save(data: Data, account: String) -> Bool {
        storage.withLock { $0[account] = data }
        return true
    }

    /// Removes any stored bytes for an account.
    ///
    /// - Parameter account: The logical keychain account identifier to clear.
    func clear(account: String) {
        _ = storage.withLock { $0.removeValue(forKey: account) }
    }
}
