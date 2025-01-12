//
//  FetchKeyError.swift
//  APIKeyReader
//
//  Created by Kraig Spear on 1/12/25.
//

import Foundation

/**
 An error was encountered when fetching a new Key
 **/
enum FetchKeyError: LocalizedError {
    /// Attempt to read a field from CloudKit. The field was missing or an unexpected type
    case missingField(named: String)
    /// Error from CloudKit when attempting to retrieve record
    case cloudKitError(error: Error)
    /// Attempt to read a record from CloudKit that is expected to exist
    case recordNotFound
    /// Airplane mode or poor network
    case networkUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .missingField(let fieldName):
            "[Developer Error] Invalid key configuration - missing \(fieldName)"
        case .cloudKitError(let error):
            "CloudKit operation failed: \(error.localizedDescription)"
        case .recordNotFound:
            "[Developer Error] Invalid Configuration Key was not found"
        case .networkUnavailable:
            "Unable to fetch API key: Please check your internet connection and try again"
        }
    }
}
