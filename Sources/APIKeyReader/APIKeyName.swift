import Foundation

/// A type-safe identifier for API keys stored in CloudKit.
///
/// Extend this type with static properties for compile-time key validation:
/// ```swift
/// extension APIKeyName {
///     static let openWeatherMap = APIKeyName(rawValue: "OpenWeatherMap")
/// }
/// ```
///
/// - SeeAlso: ``APIKeyReader``
/// - SeeAlso: ``APIKey``
public struct APIKeyName: RawRepresentable, Hashable, CustomStringConvertible, Sendable {
    /// The raw string value for the API key record name.
    public let rawValue: String

    /// A human-readable description of the key name.
    ///
    /// This value is the underlying raw key name and is suitable for display or diagnostics.
    public var description: String {
        rawValue
    }

    /// Creates an API key identifier from a raw CloudKit key name string.
    ///
    /// - Parameter rawValue: The CloudKit record name associated with the key.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
