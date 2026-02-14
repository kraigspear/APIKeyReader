import Foundation

/// Errors thrown by ``CachedKeyStorage/load()`` during cache retrieval.
///
/// ``APIKeyReader`` inspects these cases to decide whether to fall back to an
/// expired key, clear corrupted data, or propagate a keychain failure.
///
/// - SeeAlso: ``CachedKeyStorage`` for the protocol whose `load()` throws these errors.
/// - SeeAlso: ``FetchKeyError`` for errors thrown during remote key fetching.
enum LoadError: Error {
    /// The cached key exists but is older than the configured expiry.
    case expired(APIKey)
    /// The cache payload could not be decoded into an ``APIKey``.
    case decodeError
    /// The keychain returned a failure status while loading from secure storage.
    case keychainError(any Error)
    /// The cache has no value for the requested key.
    case keyDoesNotExist
}
