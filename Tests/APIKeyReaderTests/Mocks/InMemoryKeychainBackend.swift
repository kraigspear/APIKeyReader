import Foundation
import Synchronization

final class InMemoryKeychainBackend: Sendable {
    private let storage = Mutex([String: Data]())

    func load(account: String) -> Data? {
        storage.withLock { $0[account] }
    }

    func save(data: Data, account: String) -> Bool {
        storage.withLock { $0[account] = data }
        return true
    }

    func clear(account: String) {
        storage.withLock { $0.removeValue(forKey: account) }
    }
}
