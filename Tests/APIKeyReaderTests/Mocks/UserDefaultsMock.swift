//
//  UserDefaultsMock.swift
//
//
//  Created by Kraig Spear on 10/30/21.
//

import Foundation
@testable import SpearFoundation

final class UserDefaultsMock: UserDefaultsType {
    init() {}

    var objectForKey: Any?
    func object(forKey _: String) -> Any? {
        objectForKey
    }

    var urlForKey: URL?
    func url(forKey _: String) -> URL? {
        urlForKey
    }

    var arrayForKey: [Any]?
    func array(forKey _: String) -> [Any]? {
        arrayForKey
    }

    var dictionaryForKey: [String: Any]?
    func dictionary(forKey _: String) -> [String: Any]? {
        dictionaryForKey
    }

    func whenStringForKey(key: String, value: String) {
        stringForKey[key] = value
    }

    private var stringForKey: [String: String] = [:]
    func string(forKey: String) -> String? {
        stringForKey[forKey]
    }

    var stringArrayForKey: [String]?
    func stringArray(forKey _: String) -> [String]? {
        stringArrayForKey
    }

    var dataForKey: Data?
    func data(forKey _: String) -> Data? {
        dataForKey
    }

    var boolForKey: Bool!
    func bool(forKey _: String) -> Bool {
        boolForKey
    }

    var integerForKey: Int!
    func integer(forKey _: String) -> Int {
        integerForKey
    }

    var floatForKey: Float!
    func float(forKey _: String) -> Float {
        floatForKey
    }

    var doubleForKey: Double!
    func double(forKey _: String) -> Double {
        doubleForKey
    }

    var dictionaryRepresentationValue: [String: Any]!
    func dictionaryRepresentation() -> [String: Any] {
        dictionaryRepresentationValue
    }

    struct LastSetAny {
        let value: Any?
        let name: String
    }

    private(set) var lastSetAny: [LastSetAny] = []

    func set(_ value: Any?, forKey defaultName: String) {
        lastSetAny.append(LastSetAny(value: value, name: defaultName))
    }

    func set(_: Float, forKey _: String) {}

    func set(_: Double, forKey _: String) {}

    func set(_: Int, forKey _: String) {}

    func set(_: Bool, forKey _: String) {}

    func set(_: URL?, forKey _: String) {}

    func removeObject(forKey _: String) {}
}
