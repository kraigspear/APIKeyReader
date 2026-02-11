/// A type-safe wrapper for API key string values retrieved from CloudKit.
public struct APIKey: RawRepresentable, CustomStringConvertible, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}
