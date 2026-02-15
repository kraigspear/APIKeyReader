/// A type-safe wrapper for API key string values retrieved from CloudKit.
///
/// `APIKey` wraps a raw string value and provides a redacted `description`
/// to prevent accidental key exposure in logs and debug output.
///
/// - SeeAlso: ``APIKeyName``
/// - SeeAlso: ``APIKeyReader``
public struct APIKey: RawRepresentable, CustomStringConvertible, Sendable, Codable {
    public let rawValue: String

    /// Creates an API key from a raw string value.
    ///
    /// - Parameter rawValue: The secret key string.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// A redacted representation that hides the actual key value.
    public var description: String {
        "APIKey(***)"
    }
}
