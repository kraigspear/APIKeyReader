import CloudKit
import Foundation
import os

// cleanup-review: ~225 lines is appropriate — single responsibility (fetch + retry + error mapping),
// clear MARK sections, and extracting inner helpers would add indirection without reducing complexity.

/// Fetches API keys from a CloudKit public database.
///
/// Queries the `Keys` record type for a record whose `name` field matches
/// the requested ``APIKeyName``, then extracts the `key` field value.
/// Before every query the provider verifies iCloud account access, throwing
/// ``FetchKeyError/cloudKitRestricted`` when the device cannot reach CloudKit
/// at all (e.g., MDM policy or parental controls).
///
/// Transient CloudKit errors (network failures, rate limiting, service unavailability)
/// are mapped to ``FetchKeyError/networkUnavailable``. Rate-limited requests are
/// retried once using the server-provided `CKErrorRetryAfterKey` interval.
///
/// - SeeAlso: ``KeyProvider`` for the protocol this type conforms to.
/// - SeeAlso: ``APIKeyReader`` which owns this provider and adds caching on top.
/// - SeeAlso: ``FetchKeyError`` for the error types this provider throws.
struct CloudKitKeyProvider: Sendable {
    // MARK: - Properties

    private static let log = os.Logger(subsystem: "com.spearware.APIKeyReader", category: "☁️CloudKit")
    private let recordType = "Keys"
    private let maxRetryDelaySeconds: TimeInterval = 30
    private let accountStatusProvider: @Sendable () async throws -> CKAccountStatus
    private let queryProvider: @Sendable (CKQuery) async throws -> Result<CKRecord, any Error>?

    // MARK: - Initialization

    /// Creates a provider bound to the given CloudKit container.
    ///
    /// - Parameter containerIdentifier: The CloudKit container identifier
    ///   (e.g., `"iCloud.com.example.app"`).
    init(containerIdentifier: String) {
        self.init(
            containerIdentifier: containerIdentifier,
            accountStatusProvider: { try await $0.accountStatus() },
            queryProvider: { database, query in
                try await database.records(matching: query, resultsLimit: 1).matchResults.first?.1
            },
        )
    }

    init(
        containerIdentifier: String,
        accountStatusProvider: @escaping @Sendable (CKContainer) async throws -> CKAccountStatus,
        queryProvider: @escaping @Sendable (CKDatabase, CKQuery) async throws -> Result<CKRecord, any Error>?,
    ) {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.publicCloudDatabase
        self.accountStatusProvider = { try await accountStatusProvider(container) }
        self.queryProvider = { query in
            try await queryProvider(database, query)
        }
    }

    init(
        accountStatusProvider: @escaping @Sendable () async throws -> CKAccountStatus,
        queryProvider: @escaping @Sendable (CKQuery) async throws -> Result<CKRecord, any Error>?,
    ) {
        self.accountStatusProvider = accountStatusProvider
        self.queryProvider = queryProvider
    }

    /// Fetches an API key from CloudKit's public database.
    ///
    /// The method first verifies that the device has iCloud access, then queries
    /// the `Keys` record type for a matching record. Rate-limited responses are
    /// retried once using the server-provided delay.
    ///
    /// - Parameter apiKeyName: The key to look up, matched against the record's `name` field.
    /// - Returns: The ``APIKey`` read from the matching record's `key` field.
    /// - Throws: ``FetchKeyError`` describing the failure:
    ///   - ``FetchKeyError/cloudKitRestricted`` if iCloud is restricted on this device.
    ///   - ``FetchKeyError/networkUnavailable`` for transient network or service errors.
    ///   - ``FetchKeyError/recordNotFound`` if no record matches the key name.
    ///   - ``FetchKeyError/missingField(named:)`` if the record lacks the expected `key` field.
    ///   - ``FetchKeyError/cloudKitError(error:)`` for other CloudKit failures.
    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        Self.log.debug("Fetching from CloudKit Key: \(apiKeyName, privacy: .private)")

        try await checkAccountAccess()

        let query = queryForKey(apiKeyName)

        guard let firstMatch = try await fetchFirstResult(for: query) else {
            Self.log.error("No record found for key: \(apiKeyName, privacy: .private)")
            throw FetchKeyError.recordNotFound
        }
        Self.log.debug("Found result in CloudKit \(apiKeyName, privacy: .private)")

        let cloudKitRecordForKey: CKRecord
        switch firstMatch {
        case let .failure(error):
            Self.log.error("Error fetching record: \(error.localizedDescription)")
            throw FetchKeyError.cloudKitError(error: error)
        case let .success(record):
            cloudKitRecordForKey = record
        }

        Self.log.debug("Found API key for \(apiKeyName, privacy: .private)")

        guard let keyValue = cloudKitRecordForKey["key"] as? String else {
            throw FetchKeyError.missingField(named: "key")
        }
        let apiKey = APIKey(rawValue: keyValue)
        Self.log.debug("Returning API key for: \(apiKeyName, privacy: .private)")
        return apiKey
    }

    // MARK: - Private Helpers

    private func queryForKey(_ apiKeyName: APIKeyName) -> CKQuery {
        CKQuery(
            recordType: recordType,
            predicate: NSPredicate(format: "%K == %@", "name", apiKeyName.rawValue),
        )
    }

    private func fetchFirstResult(for query: CKQuery) async throws -> Result<CKRecord, any Error>? {
        do {
            return try await queryFirstMatch(for: query)
        } catch let error as CKError {
            return try await retryOnTransientError(for: query, error: error)
        }
    }

    private func retryOnTransientError(
        for query: CKQuery,
        error: CKError,
    ) async throws -> Result<CKRecord, any Error>? {
        if error.code == .managedAccountRestricted {
            throw FetchKeyError.cloudKitRestricted
        }
        guard isTransientError(error) else {
            throw FetchKeyError.cloudKitError(error: error)
        }
        guard let retryAfter = boundedRetryInterval(from: error) else {
            throw FetchKeyError.networkUnavailable
        }

        Self.log.debug("Rate limited, retrying after \(retryAfter)s")
        try await Task.sleep(for: .seconds(retryAfter))

        do {
            return try await queryFirstMatch(for: query)
        } catch let retryError as CKError {
            if retryError.code == .managedAccountRestricted {
                throw FetchKeyError.cloudKitRestricted
            }
            if isTransientError(retryError) {
                throw FetchKeyError.networkUnavailable
            }
            throw FetchKeyError.cloudKitError(error: retryError)
        }
    }

    private func queryFirstMatch(for query: CKQuery) async throws -> Result<CKRecord, any Error>? {
        try await queryProvider(query)
    }

    /// Verifies the device can access iCloud before attempting a query.
    ///
    /// Guards against restricted accounts (MDM, parental controls) and transient
    /// network issues so callers get a precise ``FetchKeyError`` rather than
    /// an opaque `CKError`.
    private func checkAccountAccess() async throws {
        let status: CKAccountStatus
        do {
            status = try await accountStatusProvider()
        } catch let error as CKError where error.code == .managedAccountRestricted {
            throw FetchKeyError.cloudKitRestricted
        } catch let error as CKError where isTransientError(error) {
            throw FetchKeyError.networkUnavailable
        } catch let error as CancellationError {
            throw error
        } catch {
            throw FetchKeyError.cloudKitError(error: error)
        }
        if status == .restricted {
            Self.log.error("iCloud access is restricted on this device")
            throw FetchKeyError.cloudKitRestricted
        }
    }

    /// Classifies CloudKit errors as transient when they are recoverable through retry
    /// or degraded fallback handling.
    ///
    /// This is intentionally conservative: only errors that may succeed on a later
    /// attempt are considered transient so the caller can distinguish permanent failures
    /// from temporary service/network conditions.
    private func isTransientError(_ error: CKError) -> Bool {
        switch error.code {
        case .networkFailure, .networkUnavailable,
             .serviceUnavailable, .requestRateLimited,
             .serverResponseLost, .zoneBusy:
            true
        default:
            false
        }
    }

    /// Extracts the server-recommended retry delay from CloudKit's metadata.
    ///
    /// A non-nil delay (for example from ``CKErrorRetryAfterKey``) is used to perform
    /// a single bounded retry and avoid busy-loop behavior under rate limiting.
    private func retryInterval(from error: CKError) -> TimeInterval? {
        (error as NSError).userInfo[CKErrorRetryAfterKey] as? TimeInterval
    }

    private func boundedRetryInterval(from error: CKError) -> TimeInterval? {
        guard let delay = retryInterval(from: error), delay.isFinite else {
            return nil
        }
        if delay < 0 {
            return nil
        }
        return min(delay, maxRetryDelaySeconds)
    }
}

// MARK: - KeyProvider

extension CloudKitKeyProvider: KeyProvider {}
