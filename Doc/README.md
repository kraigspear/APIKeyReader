# APIKeyReader Documentation

This folder contains design documentation explaining the rationale behind APIKeyReader's implementation. Each document focuses on **why** decisions were made, not what the code does.

## Architecture

- [Architecture](Architecture.md) — High-level system design: actor-based coordination, protocol abstraction, error handling strategy, and component responsibilities
- [PlatformRequirements](PlatformRequirements.md) — Why iOS 26+ / macOS 26+ and Swift 6.2

## Topics

- [Caching](Caching.md) — Why cache at the actor layer, expiration strategy, expired key fallback, and cache lifecycle management
- [CloudKitKeyProvider](CloudKitKeyProvider.md) — CloudKit integration: query limits, account access checks, retry logic, and error classification
- [ErrorHandling](ErrorHandling.md) — Error type hierarchy, why LoadError.expired contains the key, transient vs permanent error classification, and localized messages
- [KeychainStorage](KeychainStorage.md) — Why synchronous keychain operations, SecAccessControl decisions, update-then-add pattern, and security constraints
- [LoggingPrivacy](LoggingPrivacy.md) — Why .private annotations for key names, os.Logger over print(), and production log redaction strategy
- [Protocols](Protocols.md) — Why KeyProvider and CachedKeyStorage protocols, dependency injection pattern, and Sendable conformance requirements
- [Strings](Strings.md) — Why centralize error messages, String(localized:) over NSLocalizedString, audience-based comments, and localization workflow

## Legacy Documentation

- [APIKeyReader](APIKeyReader.md) — Earlier documentation (superseded by Architecture.md)
- [ErrorResilience](ErrorResilience.md) — Earlier documentation (superseded by ErrorHandling.md and Caching.md)
- [LocalStorage](LocalStorage.md) — Earlier documentation (superseded by KeychainStorage.md and Caching.md)

## Quick Reference

### Core Design Principles

1. **Availability over freshness** — Return expired keys during network failures to maintain app functionality
2. **Type safety** — Use `APIKeyName` enum for compile-time key validation
3. **Actor isolation** — Serialize access to shared state (task deduplication, storage cache)
4. **Protocol abstraction** — Decouple CloudKit and Keychain from coordination logic
5. **Privacy-first logging** — Redact sensitive data (.private) while preserving error diagnostics (.public)

### Key Architectural Decisions

| Decision | Rationale | Document |
|----------|-----------|----------|
| Actor-based `APIKeyReader` | Prevents race conditions on shared mutable state | [Architecture](Architecture.md) |
| Protocol-based providers | Enables testing, future backend swaps | [Protocols](Protocols.md) |
| Keychain over UserDefaults | Security best practices, access control | [KeychainStorage](KeychainStorage.md) |
| Expired key fallback | Graceful degradation in offline scenarios | [ErrorHandling](ErrorHandling.md) |
| Single retry on rate limiting | Balances responsiveness with quota conservation | [CloudKitKeyProvider](CloudKitKeyProvider.md) |
| Centralized `Strings.swift` | Localization-ready, single source of truth | [Strings](Strings.md) |
| Minute-granular expiration | Matches API key rotation cadence | [Caching](Caching.md) |
| `.private` privacy annotations | Redact key names in production logs | [LoggingPrivacy](LoggingPrivacy.md) |

### Recent Changes (cloudkit-error-handling-improvements branch)

This documentation covers the following improvements:

- **CloudKit error handling** — Transient error classification, rate limiting retry with bounded delay, account access pre-checks
- **Keychain storage** — Migration from UserDefaults to Keychain, `SecAccessControl` with device-only access, task-local test backend injection
- **Centralized Strings.swift** — Localization-ready error messages with audience-based comments using `String(localized:)`
- **Protocol extraction** — `KeyProvider`, `CachedKeyStorage` protocols at package root, adjacent to `APIKeyReader` coordinator
- **Logging privacy** — `.private` annotations for key names and account identifiers
- **CloudKit query limits** — `resultsLimit: 1` optimization for unique key queries
- **Access attribute preservation** — Explicit preservation of `SecAccessControl` and `kSecAttrAccessible` during keychain updates

## Design Philosophy

This library prioritizes:

1. **Safety** — Swift 6 concurrency eliminates data races; Keychain protects credentials
2. **Resilience** — Network failures don't cause app failures; expired keys serve as fallback
3. **Simplicity** — Modern platform requirements enable cleaner code without legacy compatibility layers
4. **Performance** — Task deduplication prevents redundant network calls; Keychain caching minimizes latency

Documentation focuses on **why** decisions were made, not what the code does. Read the source for implementation details.

## Contributing

When adding new features or changing design decisions:

1. Update the relevant documentation to explain **why** the change was made
2. Include alternative approaches considered and why they were rejected
3. Update this README if adding a new topic document
4. Keep examples realistic and focused on non-obvious decisions

## Related Resources

- [CLAUDE.md](../CLAUDE.md) — Project overview and development commands
- [README.md](../README.md) — Usage examples and integration guide
- [Package.swift](../Package.swift) — Platform and dependency configuration
