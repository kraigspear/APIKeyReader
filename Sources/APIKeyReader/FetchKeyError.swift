import Foundation

/// An error encountered while fetching an API key.
///
/// Use this type to distinguish expected CloudKit and network failures from
/// configuration issues.
///
/// - SeeAlso: ``APIKeyReader``
public enum FetchKeyError: LocalizedError {
    /// Attempt to read a field from CloudKit. The field was missing or an unexpected type
    case missingField(named: String)
    /// Error from CloudKit when attempting to retrieve record
    case cloudKitError(error: Error)
    /// Attempt to read a record from CloudKit that is expected to exist
    case recordNotFound
    /// iCloud access is restricted on this device (for example by MDM or parental controls).
    case cloudKitRestricted
    /// Airplane mode or poor network
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case let .missingField(fieldName):
            String(format: Strings.FetchKeyError.missingField, fieldName)
        case let .cloudKitError(error):
            String(format: Strings.FetchKeyError.cloudKitError, error.localizedDescription)
        case .recordNotFound:
            Strings.FetchKeyError.recordNotFound
        case .cloudKitRestricted:
            Strings.FetchKeyError.cloudKitRestricted
        case .networkUnavailable:
            Strings.FetchKeyError.networkUnavailable
        }
    }
}
