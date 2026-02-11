import Foundation

/// A type-safe identifier for API keys stored in CloudKit.
///
/// Extend this type with static properties for compile-time key validation:
/// ```swift
/// extension APIKeyName {
///     static let openWeatherMap = APIKeyName(rawValue: "OpenWeatherMap")
/// }
/// ```
public struct APIKeyName: RawRepresentable, Hashable, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}
