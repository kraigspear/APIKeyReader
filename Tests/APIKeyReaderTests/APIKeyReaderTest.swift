//
//  APIKeyReaderTest.swift
//
//
//  Created by Kraig Spear on 10/30/21.
//

@testable import APIKeyReader
@testable import SpearFoundation
import XCTest

final class APIKeyReaderTest: XCTestCase {
    private var defaultsMock: UserDefaultsMock!
    private var apiKeyCloudKitMock: APIKeyCloudKitMock!

    private var subjectUnderTest: APIKeyReader!

    override func setUp() async throws {
        defaultsMock = UserDefaultsMock()
        apiKeyCloudKitMock = APIKeyCloudKitMock()
        subjectUnderTest = APIKeyReader(userDefaults: defaultsMock,
                                        apiKeyCloudKit: apiKeyCloudKitMock)
    }

    /**
     1. The Key is always retrieve from defaults if it exist in defaults
     2. We do not want to retrieve the key from CloudKit if it does exist in Defaults
     */
    func testWhenKeyIsInDefaultsThenDefaultsIsUsed() async {
        let expectedKey = "CD933D39-F0DB-426D-8EC4-9CCC379C05F5"
        defaultsMock.whenStringForKey(key: APIKeyName.openWeatherMap.rawValue,
                                      value: expectedKey)

        do {
            let key = try await subjectUnderTest.apiKey(named: .openWeatherMap)
            XCTAssertEqual(expectedKey, key)
        } catch {
            XCTFail("Error not expected")
        }
    }

    /**
     Key was not found in defaults
     Key was retrieved from CloudKit
     */
    func testWhenKeyIsNotInDefaultsKeyIsRetrievedFromCloudKit() async {
        let expectedKey = "D848F0E6-820E-46AD-A361-255CF1954843"
        apiKeyCloudKitMock.whenAPIKeyWithName(key: .openWeatherMap, value: expectedKey)

        do {
            let key = try await subjectUnderTest.apiKey(named: .openWeatherMap)
            XCTAssertEqual(expectedKey, key)
        } catch {
            XCTFail("Error not expected")
        }
    }

    func testKeyIsRefreshedWhenUserInfoIsFromCKSubscription() async {
        let expectedKey = "C38CC437-5ACD-4CF9-B1E2-B21DFA34212D"

        apiKeyCloudKitMock.whenFetchNewKeyReturnsKey(key: expectedKey,
                                                     named: APIKeyName.openWeatherMap.rawValue)

        do {
            try await subjectUnderTest.refreshKey(userInfo: [:])
            XCTAssertEqual(1, defaultsMock.lastSetAny.count)
            let savedKey = defaultsMock.lastSetAny.first!.value as! String
            XCTAssertEqual(expectedKey, savedKey)
        } catch {
            XCTFail("Unexpected error")
        }
    }
}
