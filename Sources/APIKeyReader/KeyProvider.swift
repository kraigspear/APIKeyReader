/// Fetches API keys from a remote source.
///
/// Conforming types provide the key fetching strategy used by ``APIKeyReader``.
/// Implementations should handle their own error mapping and retry logic.
///
/// - SeeAlso: ``CloudKitKeyProvider`` for the production implementation.
/// - SeeAlso: ``APIKeyReader`` which owns the provider and adds caching on top.
/// - SeeAlso: ``FetchKeyError`` for the error types implementations throw.
protocol KeyProvider: Sendable {
    /// Fetches an API key from the remote source.
    ///
    /// - Parameter apiKeyName: The name of the key to retrieve.
    /// - Returns: The fetched API key.
    /// - Throws: ``FetchKeyError`` describing the fetch failure.
    func fetchAPIKey(_ apiKeyName: APIKeyName) async throws -> APIKey
}
