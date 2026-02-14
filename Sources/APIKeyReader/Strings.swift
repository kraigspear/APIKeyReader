import Foundation

/// Centralized localized strings for the APIKeyReader module.
///
/// All user-facing and developer-facing error messages are defined here
/// using `String(localized:defaultValue:comment:)` for localization support.
enum Strings {
    enum FetchKeyError {
        static let missingField = String(
            localized: "fetch_key_error_missing_field",
            defaultValue: "Developer Error: Invalid key configuration - missing %@",
            comment: "Developer-facing error when required CloudKit field is absent or not a string.",
        )

        static let cloudKitError = String(
            localized: "fetch_key_error_cloudkit_error",
            defaultValue: "CloudKit operation failed: %@",
            comment: "Error when a CloudKit request returns an error while fetching an API key.",
        )

        static let recordNotFound = String(
            localized: "fetch_key_error_record_not_found",
            defaultValue: "Developer Error: Invalid configuration. The requested key was not found.",
            comment: "Developer-facing error when a required API key record does not exist in CloudKit.",
        )

        static let cloudKitRestricted = String(
            localized: "fetch_key_error_cloudkit_restricted",
            defaultValue: "iCloud access is restricted on this device",
            comment: "User-facing error when iCloud access is restricted by policy or account settings.",
        )

        static let networkUnavailable = String(
            localized: "fetch_key_error_network_unavailable",
            defaultValue: "Unable to fetch API key: Please check your internet connection and try again",
            comment: "User-facing error when a network failure blocks API key fetching.",
        )
    }
}
