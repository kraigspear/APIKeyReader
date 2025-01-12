//
//  APIKey.swift
//  APIKeyReader
//
//  Created by Kraig Spear on 1/12/25.
//

public struct APIKey: RawRepresentable, CustomStringConvertible, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    public var description: String {
        rawValue
    }
}
