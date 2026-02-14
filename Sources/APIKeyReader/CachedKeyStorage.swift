/// A contract for storing and retrieving cached API keys.
///
/// Conforming types provide persistence for API keys with expiration-based invalidation.
///
/// - SeeAlso: ``LocalStorage`` for the Keychain-backed production implementation.
/// - SeeAlso: ``APIKeyReader`` which uses this protocol to cache fetched keys.
/// - SeeAlso: ``LoadError`` for errors thrown by ``load()``.
/// - SeeAlso: ``APIKeyName``
protocol CachedKeyStorage: Sendable {
    /// Loads the cached API key.
    ///
    /// - Returns: The cached API key if it exists and has not expired.
    /// - Throws: ``LoadError/keyDoesNotExist`` if no cached key is found,
    ///   ``LoadError/expired(_:)`` if the key exists but has expired,
    ///   or ``LoadError/decodeError`` if the stored data is corrupted.
    func load() async throws -> APIKey

    /// Removes the cached key from storage.
    func clear() async

    /// Saves an API key to the cache with the given expiration.
    ///
    /// Passing `nil` for `value` clears the cached entry.
    ///
    /// - Parameters:
    ///   - value: The API key to cache, or `nil` to clear.
    ///   - expiresMinutes: Number of minutes until the cached key expires.
    func save(value: APIKey?, expiresMinutes: Int) async
}
