//
//  APIKeyCloudKit.swift
//
//
//  Created by Kraig Spear on 10/27/21.
//

import CloudKit
import Foundation
import os

/**
 An error was encountered when fetching a new Key
 **/
public enum FetchKeyError: Error {
    /// Attempt to read a field from CloudKit. The field was missing or an unexpected type
    case missingField(named: String)
    /// UserInfo passed in can't be converted to a CKNotification
    case userInfoNotCKNotification
    /// Error from CloudKit when attempting to retrieve record
    case cloudKitError(error: Error)
    /// Attempt to read a record from CloudKit that is expected to exist
    case recordNotFound
}

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
    func extract(from record: CKRecord) throws -> String {
        let log = os.Logger(subsystem: "com.spearware.foundation", category: "☁️CloudKit")
        let fieldName = rawValue
        if let value = record[fieldName] as? String {
            log.debug("Field named: \(fieldName) found value of: \(value)")
            return value
        }
        log.error("Record was found, but not the field: \(fieldName)")
        throw FetchKeyError.missingField(named: fieldName)
    }
}

public struct APIKeyCloudKit: Sendable {
    private let log = os.Logger(subsystem: "com.spearware.foundation", category: "☁️CloudKit")
    private let recordType = "Keys"
    private let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    // MARK: - APIKeyCloudKitType

    /**
     Fetches an API Key from CloudKit
     - parameter named: Name of the key to fetch from CloudKit
     - returns: API key for a given name
     - throws FetchKeyError.cloudKitError: If CloudKit throws an error
     */
    public func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        log.debug("Fetching from CloudKit Key: \(apiKeyName)")

        func performQueryReturningFirstResult() async throws -> CKRecord {
            let query = queryForKey(apiKeyName)
            log.debug("Performing query \(query)")
            let firstMatchedResult = try await database.records(matching: query).matchResults.first?.1
            log.debug("Finished query \(query)")

            if let firstMatch = firstMatchedResult {
                log.debug("Found result in CloudKit \(apiKeyName.rawValue)")

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
        }

        let cloudKitRecordForKey = try await performQueryReturningFirstResult()
        log.debug("Found API key for \(apiKeyName.rawValue)")

        let apiKey = try KeyField.key.extract(from: cloudKitRecordForKey)
        log.debug("Returning API key for: \(apiKeyName)")
        return apiKey
    }

    /**
     Called when a silent CloudKit push is received to trigger
     getting a refreshed API Key

     - parameter for: CKRecord.ID of the record to fetch
     - returns: New key value, or nil if the key could not be retrieved
     */
    public func fetchNewKey(for recordID: CKRecord.ID) async throws -> (name: String, key: String) {
        log.debug("fetchNewKey for CKRecord.ID: \(recordID)")

        let record = try await database.record(for: recordID)

        let keyName = try KeyField.name.extract(from: record)
        let keyValue = try KeyField.key.extract(from: record)

        return (name: keyName, key: keyValue)
    }

    // MARK: - Private

    private func queryForKey(_ apiKeyName: APIKeyName) -> CKQuery {
        CKQuery(recordType: recordType, predicate: predicateForKey(apiKeyName))
    }

    private func predicateForKey(_ apiKeyName: APIKeyName) -> NSPredicate {
        NSPredicate(format: "\(KeyField.name.rawValue) == %@", argumentArray: [apiKeyName.rawValue])
    }

    private var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).publicCloudDatabase
    }
}
