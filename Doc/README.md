# APIKeyReader Documentation

This folder contains design documentation explaining the rationale behind APIKeyReader's implementation.

## Architecture

- [APIKeyReader](APIKeyReader.md) — Actor-based coordination, task deduplication, and SwiftUI integration
- [ErrorResilience](ErrorResilience.md) — Fallback strategies, stale-data tolerance, and graceful degradation
- [PlatformRequirements](PlatformRequirements.md) — Why iOS 26+ / macOS 26+ and Swift 6.2

## Topics

- [LocalStorage](LocalStorage.md) — Why Keychain instead of UserDefaults, update-or-add pattern, and access control policies

## Design Philosophy

This library prioritizes:

1. **Safety** — Swift 6 concurrency eliminates data races; Keychain protects credentials
2. **Resilience** — Network failures don't cause app failures; expired keys serve as fallback
3. **Simplicity** — Modern platform requirements enable cleaner code without legacy compatibility layers
4. **Performance** — Task deduplication prevents redundant network calls; Keychain caching minimizes latency

Documentation focuses on **why** decisions were made, not what the code does. Read the source for implementation details.

## Related Resources

- [CLAUDE.md](../CLAUDE.md) — Project overview and development commands
- [README.md](../README.md) — Usage examples and integration guide (if exists)
- [Package.swift](../Package.swift) — Platform and dependency configuration
