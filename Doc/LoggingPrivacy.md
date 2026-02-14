# Logging Privacy

## Overview

APIKeyReader uses os.Logger with privacy annotations to control what data appears in system logs, crash reports, and diagnostics. The library balances debuggability with protecting sensitive key names and values.

## Key Design Decisions

### Why .private for Key Names

All logs containing `apiKeyName` use `.private` privacy:

```swift
Log.logger.debug("Fetching APIKey: \(apiKeyName, privacy: .private)")
```

**Rationale:**

Key names may reveal:
- Business logic (e.g., `stripeProductionAPI`, `stagingBackend`)
- Third-party integrations (e.g., `openWeatherMap`, `twilioSMS`)
- Internal architecture details

Marking them `.private` ensures:
- Production system logs **redact** the key name (`<private>`)
- Developer debug builds (with logging enabled) **show** the key name
- Crash reports don't leak integration details to third-party analytics

### Why APIKey.description Redacts Values

The `APIKey` type hides its raw value in string representation:

```swift
public struct APIKey: CustomStringConvertible {
    public let rawValue: String

    public var description: String {
        "APIKey(***)"
    }
}
```

**Why not expose the real key?**

If `description` returned `rawValue`:
- Accidentally logging `apiKey` would expose secrets in plain text
- Debug print statements would leak keys to console
- Crash reports might include full key values

The redacted description prevents accidental exposure while still indicating an `APIKey` instance exists.

### Why Debug Builds Log More

Logging is wrapped in `#if DEBUG` blocks:

```swift
#if DEBUG
Log.logger.debug("Fetching APIKey: \(apiKeyName, privacy: .private)")
#endif
```

**Rationale:**

- **Release builds** minimize log overhead and reduce log clutter in production
- **Debug builds** provide detailed flow information for development and testing
- `.private` privacy ensures even debug builds respect privacy when system logging is active

This pattern allows verbose debugging without polluting production logs.

### Why Errors Are Logged with .public

Error messages use `.public` privacy:

```swift
Log.logger.error(
    "Local storage read failed for \(apiKeyName, privacy: .public); falling back to provider: \(String(describing: error), privacy: .public)"
)
```

**Why public for errors but sensitive for key names?**

- **Error types** (e.g., `LoadError.expired`, `FetchKeyError.networkUnavailable`) don't expose secrets
- **Error descriptions** are already sanitized via `LocalizedError` (no raw key values)
- **Public logging** ensures crash reports and diagnostics include actionable error information

This balance allows debugging production issues without leaking sensitive data.

### Why KeychainStorage Logs Account Names as .private

Keychain operations log the account parameter with `.private` privacy:

```swift
logger.debug("Keychain read operation started for account: \(account, privacy: .private)")
```

**Rationale:**

The account name is `APIKeyName.rawValue`, which reveals integration details (same rationale as logging `apiKeyName`). Redacting it prevents keychain operation logs from leaking business logic.

### Why os.Logger Over print()

The library uses `os.Logger` instead of `print()`:

```swift
private enum Log {
    static let logger = os.Logger(subsystem: "com.spearware.APIKeyReader", category: "🔑APIKey")
}
```

**Benefits:**

1. **Privacy annotations** — `.private` and `.public` control redaction
2. **Structured logging** — Logs include timestamps, process ID, subsystem metadata
3. **Performance** — `os.Logger` is optimized for high-frequency logging (no overhead in release builds if unused)
4. **Console.app integration** — Logs appear in macOS Console with filtering support
5. **System diagnostics** — Crash reports include recent log entries automatically

`print()` provides none of these features and clutters stdout without structure.

### Why Subsystem and Category

Logs use a specific subsystem and category:

```swift
os.Logger(subsystem: "com.spearware.APIKeyReader", category: "🔑APIKey")
```

**Why these values?**

- **Subsystem** (`com.spearware.APIKeyReader`) — Identifies the library in system logs, allowing filtering by package
- **Category** (`🔑APIKey`) — Groups related logs together and adds a visual identifier in Console.app
- **Emoji prefix** — Makes logs easy to spot when scanning mixed app/framework logs

This structure supports log aggregation tools (e.g., filtering all APIKeyReader logs) and improves manual debugging.

### Why All Components Share One Subsystem

All loggers in the package use `com.spearware.APIKeyReader` as their subsystem, differentiated by category:

```swift
// APIKeyReader / LocalStorage / KeychainStorage
os.Logger(subsystem: "com.spearware.APIKeyReader", category: "🔑APIKey")

// CloudKitKeyProvider
os.Logger(subsystem: "com.spearware.APIKeyReader", category: "☁️CloudKit")
```

A single subsystem makes log filtering consistent — one filter captures all package activity, while the category distinguishes the component.

## Privacy Annotation Best Practices

| Data Type | Privacy Level | Example |
|-----------|--------------|---------|
| API key values | `.private` (or redacted in description) | `APIKey(***)` |
| Key names (`APIKeyName`) | `.private` | `\(apiKeyName, privacy: .private)` |
| Error types | `.public` | `\(error, privacy: .public)` |
| Keychain account names | `.private` | `\(account, privacy: .private)` |
| CloudKit container IDs | `.public` | Container IDs are not secrets |
| OSStatus codes | `.public` | Numeric error codes are safe |

## Log Redaction Examples

### Debug Build (Development)

```
[APIKeyReader] Fetching APIKey: OpenWeatherMap
[APIKeyReader] Key not found or expired in keychain for: OpenWeatherMap
[CloudKit] Fetching from CloudKit Key: OpenWeatherMap
```

### Release Build (Production)

```
[APIKeyReader] Fetching APIKey: <private>
[APIKeyReader] Key not found or expired in keychain for: <private>
[CloudKit] Fetching from CloudKit Key: <private>
```

### Error Logs (Always Public)

```
[APIKeyReader] Local storage read failed for OpenWeatherMap; falling back to provider: LoadError.keychainError
[CloudKit] Error fetching record: CKError.networkUnavailable
```

## Enabling Detailed Logging in Production

To view redacted logs during production debugging:

### iOS/macOS Console.app

1. Open Console.app
2. Filter by subsystem: `com.spearware.APIKeyReader`
3. Enable "Include Sensitive Data" in Action menu
4. Logs show full key names (requires developer mode)

### Xcode Debug Console

Set environment variable:

```swift
// In scheme settings, add:
OS_ACTIVITY_MODE = "enable"
```

Then run with Instruments or Console.app to see private data.

## See Also

- [Architecture](Architecture.md) — Overall logging strategy
- [ErrorHandling](ErrorHandling.md) — Error message structure
