//
//  APIKeyCloudKitMock.swift
//
//
//  Created by Kraig Spear on 10/30/21.
//

@testable import APIKeyReader
import CloudKit
import Foundation

final class APIKeyCloudKitMock: APIKeyCloudKitType {
    private var apiKeyValues: [APIKeyName: APIKey] = [:]

    func whenAPIKeyWithName(key: APIKeyName, value: APIKey) {
        apiKeyValues[key] = value
    }

    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey {
        if let apiKey = apiKeyValues[apiKeyName] {
            return apiKey
        }
        throw FetchKeyError.recordNotFound
    }

    var subscriptionIDValue: CKSubscription.ID!
    func subscribeToCloudKitChanges(apiKeyName _: APIKeyName) async throws -> CKSubscription.ID {
        subscriptionIDValue
    }

    var fetchNewKeyName: String!
    var fetchNewKeyKey: String!

    func whenFetchNewKeyReturnsKey(key: String, named: String) {
        fetchNewKeyKey = key
        fetchNewKeyName = named
    }

    func fetchNewKey(userInfo _: [AnyHashable: Any]) async throws -> (name: String, key: String) {
        (name: fetchNewKeyName, key: fetchNewKeyKey)
    }
}
