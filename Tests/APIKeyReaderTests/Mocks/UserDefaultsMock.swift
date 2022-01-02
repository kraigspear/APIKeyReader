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
    func object(forKey defaultName: String) -> Any? {
        objectForKey
    }

    var urlForKey: URL?
    func url(forKey: String) -> URL? {
        urlForKey
    }

    var arrayForKey: [Any]?
    func array(forKey: String) -> [Any]? {
        arrayForKey
    }

    var dictionaryForKey: [String : Any]?
    func dictionary(forKey: String) -> [String : Any]? {
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
    func stringArray(forKey: String) -> [String]? {
        stringArrayForKey
    }

    var dataForKey: Data?
    func data(forKey: String) -> Data? {
        dataForKey
    }

    var boolForKey: Bool!
    func bool(forKey: String) -> Bool {
        boolForKey
    }

    var integerForKey: Int!
    func integer(forKey: String) -> Int {
        integerForKey
    }

    var floatForKey: Float!
    func float(forKey: String) -> Float {
        floatForKey
    }

    var doubleForKey: Double!
    func double(forKey: String) -> Double {
        doubleForKey
    }

    var dictionaryRepresentationValue: [String : Any]!
    func dictionaryRepresentation() -> [String : Any] {
        dictionaryRepresentationValue
    }

    struct LastSetAny {
        let value: Any?
        let name: String
    }

    private (set) var lastSetAny: [LastSetAny] = []

    func set(_ value: Any?, forKey defaultName: String) {
        lastSetAny.append(LastSetAny(value: value, name: defaultName))
    }

    func set(_ value: Float, forKey: String) {

    }

    func set(_ value: Double, forKey: String) {

    }

    func set(_ value: Int, forKey: String) {

    }

    func set(_ value: Bool, forKey: String) {

    }

    func set(_ value: URL?, forKey: String) {

    }

    func removeObject(forKey: String) {

    }


}
