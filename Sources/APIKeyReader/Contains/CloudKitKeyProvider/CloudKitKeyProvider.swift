//
//  CloudKitKeyProvider.swift
//
//
//  Created by Kraig Spear on 10/27/21.
//

import CloudKit
import Foundation
import os

/// Name of fields in the Keys table
private enum KeyField: String {
    /// Name of the API Key
    case name
    /// API key value
    case key

    /**
     Extract the value of the key from a CKRecord
     - parameter record: The CKRecord to extract from
     - throws FetchKeyError.missingField: If the key can isn't found or the expected type
     */
    func extract(from record: CKRecord) throws -> APIKey {
        let log = os.Logger(subsystem: "com.spearware.foundation", category: "☁️CloudKit")
        let fieldName = rawValue
        if let value = record[fieldName] as? String {
            log.debug("Field named: \(fieldName) found value of: \(value)")
            return .init(rawValue: value)
        }
        log.error("Record was found, but not the field: \(fieldName)")
        throw FetchKeyError.missingField(named: fieldName)
    }
}

struct CloudKitKeyProvider: Sendable {
    private let log = os.Logger(subsystem: "com.spearware.foundation", category: "☁️CloudKit")
    private let recordType = "Keys"
    private let containerIdentifier: String

    init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    // MARK: - APIKeyCloudKitType

    /**
     Fetches an API Key from CloudKit
     - parameter named: Name of the key to fetch from CloudKit
     - returns: API key for a given name
     - throws FetchKeyError.cloudKitError: If CloudKit throws an error
     */
    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        log.debug("Fetching from CloudKit Key: \(apiKeyName)")

        func performQueryReturningFirstResult() async throws -> CKRecord {
            let query = queryForKey(apiKeyName)
            log.debug("Performing query \(query)")

            if let firstMatch = try await fetchFirstResult() {
                log.debug("Finished query \(query)")
                log.debug("Found result in CloudKit \(apiKeyName)")

                switch firstMatch {
                case let .failure(error):
                    log.error("Error fetching record: \(error.localizedDescription)")
                    throw FetchKeyError.cloudKitError(error: error)
                case let .success(record):
                    return record
                }
            }

            log.error("Query returned 0 results \(query)")

            throw FetchKeyError.recordNotFound

            func fetchFirstResult() async throws -> Result<CKRecord, any Error>? {
                do {
                    return try await database.records(matching: query).matchResults.first?.1
                } catch let error as CKError {
                    if error.code == .networkFailure || error.code == .networkUnavailable {
                        throw FetchKeyError.networkUnavailable
                    } else {
                        throw FetchKeyError.cloudKitError(error: error)
                    }
                }
            }
        }

        let cloudKitRecordForKey = try await performQueryReturningFirstResult()
        log.debug("Found API key for \(apiKeyName)")

        let apiKey = try KeyField.key.extract(from: cloudKitRecordForKey)
        log.debug("Returning API key for: \(apiKeyName)")
        return apiKey
    }

    // MARK: - Private

    private func queryForKey(_ apiKeyName: APIKeyName) -> CKQuery {
        CKQuery(
            recordType: recordType,
            predicate: predicateForKey(apiKeyName)
        )
    }

    private func predicateForKey(_ apiKeyName: APIKeyName) -> NSPredicate {
        NSPredicate(
            format: "\(KeyField.name.rawValue) == %@", argumentArray: [apiKeyName.rawValue]
        )
    }

    private var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).publicCloudDatabase
    }
}
