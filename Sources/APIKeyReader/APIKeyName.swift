//
//  APIKeyName.swift
//  APIKeyReader
//
//  Created by Kraig Spear on 1/12/25.
//

import Foundation

public struct APIKeyName: RawRepresentable, Hashable, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String {
        rawValue
    }
}
