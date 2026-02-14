@testable import APIKeyReader

// MARK: - TestStorageState

actor TestStorageState {
    enum LoadBehavior {
        case value(APIKey)
        case error(any Error)
    }

    var loadBehavior: LoadBehavior
    var clearCallCount = 0
    var saveCallCount = 0
    var lastSavedKey: APIKey?

    init(loadBehavior: LoadBehavior) {
        self.loadBehavior = loadBehavior
    }

    func currentLoadBehavior() -> LoadBehavior {
        loadBehavior
    }

    func markCleared() {
        clearCallCount += 1
        loadBehavior = .error(LoadError.keyDoesNotExist)
    }

    func markSaved(_ value: APIKey?) {
        saveCallCount += 1
        lastSavedKey = value
    }
}

// MARK: - TestCachedKeyStorage

actor TestCachedKeyStorage: CachedKeyStorage {
    let state: TestStorageState

    init(state: TestStorageState) {
        self.state = state
    }

    func load() async throws -> APIKey {
        switch await state.currentLoadBehavior() {
        case let .value(key):
            return key
        case let .error(error):
            throw error
        }
    }

    func clear() async {
        await state.markCleared()
    }

    func save(value: APIKey?, expiresMinutes _: Int) async {
        await state.markSaved(value)
    }
}

// MARK: - SaveFailureStorage

actor SaveFailureStorage: CachedKeyStorage {
    let state: TestStorageState
    private(set) var didAttemptSave = false

    init(state: TestStorageState) {
        self.state = state
    }

    func load() async throws -> APIKey {
        switch await state.currentLoadBehavior() {
        case let .value(key):
            return key
        case let .error(error):
            throw error
        }
    }

    func clear() async {
        await state.markCleared()
    }

    func save(value: APIKey?, expiresMinutes _: Int) async {
        didAttemptSave = true
        await state.markSaved(value)
    }
}

// MARK: - StorageFactoryProbe

actor StorageFactoryProbe {
    private var clearedIDsStorage: [Int] = []

    func clearedIDs() -> [Int] {
        clearedIDsStorage
    }

    func recordClear(id: Int) {
        clearedIDsStorage.append(id)
    }
}

// MARK: - IdentifiedCachedKeyStorage

actor IdentifiedCachedKeyStorage: CachedKeyStorage {
    let id: Int
    let probe: StorageFactoryProbe
    let key: APIKey

    init(id: Int, probe: StorageFactoryProbe, key: APIKey) {
        self.id = id
        self.probe = probe
        self.key = key
    }

    func load() async throws -> APIKey {
        key
    }

    func clear() async {
        await probe.recordClear(id: id)
    }

    func save(value _: APIKey?, expiresMinutes _: Int) async {}
}
