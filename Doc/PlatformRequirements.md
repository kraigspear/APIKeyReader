# Platform Requirements

## Overview

APIKeyReader targets iOS 26+ and macOS 26+ with Swift 6.2. These platform requirements reflect deliberate architectural choices around concurrency safety and framework availability.

## Key Design Decisions

### Why iOS 26 / macOS 26

The package sets aggressive minimum platform versions:

```swift
// Package.swift
platforms: [
    .iOS(.v26),
    .macOS(.v26),
]
```

This decision enables several critical capabilities:

**Swift 6.2 Full Concurrency Checking**
- Complete data race safety enforcement at compile time
- Actor isolation checking without opt-in flags
- Sendable conformance verification for all types
- No backward compatibility compromises with pre-concurrency patterns

**CloudKit Modern Async APIs**
- `CKDatabase.records(matching:)` with native async/await
- Result-based query APIs instead of completion handlers
- Task-based cancellation propagation
- No bridging layers or continuation wrappers required

**Keychain Security Framework Stability**
- Modern Security.framework with updated OSStatus codes
- Improved error reporting for debugging
- Enhanced Secure Enclave integration
- Consistent behavior across all target platforms

**Observable Macro Support**
- Native `@Observable` macro for SwiftUI integration
- No need for Combine publishers or `ObservableObject`
- Simplified state management in SwiftUI views
- Better performance than publisher-based observation

### Why Swift 6.2

The Swift tools version is explicitly set to 6.2:

```swift
// swift-tools-version: 6.2
```

This requirement enables:

**Concurrency Safety Features:**
- `nonisolated(unsafe)` for controlled opt-outs of isolation checking
- Improved actor re-entrancy detection
- Complete checking mode enabled by default
- Better diagnostics for isolation violations

**Language Improvements:**
- Implicit `Sendable` conformance inference for simple types
- Enhanced closure capture checking
- Better async let syntax and error propagation
- Improved generic type inference

**Package Manager Features:**
- Trait-based dependency conditions
- Improved build performance
- Better caching and incremental builds
- Enhanced test target support

### Trade-offs of High Platform Floors

**Advantages:**
1. **Simpler codebase** — No version checks or fallback paths for older APIs
2. **Better safety** — Swift 6 concurrency eliminates entire classes of bugs
3. **Smaller binary** — No compatibility shims or legacy code paths
4. **Easier maintenance** — Single code path reduces testing matrix

**Disadvantages:**
1. **Limited adoption** — Apps targeting older OS versions can't use the library
2. **Ecosystem friction** — Many Swift packages still support iOS 15+
3. **Delayed updates** — Organizations slow to adopt new OS versions can't benefit

For this library, the advantages outweigh the disadvantages because:
- API key management is a foundational concern that benefits from maximum safety guarantees
- Apps using CloudKit are typically modern and update regularly
- The library is small and focused — maintaining backward compatibility would add significant complexity relative to total code volume
- Thread safety bugs in credential management can have security implications

### Alternative Approaches Rejected

**Support iOS 15+ with availability checks:**
```swift
// NOT used — rejected approach
if #available(iOS 16, *) {
    try await database.records(matching: query)
} else {
    // Completion handler fallback
    database.perform(query) { records, error in
        // Bridge to async/await with continuations
    }
}
```

Rejected because:
- Doubles code paths and testing surface area
- Loses compile-time concurrency safety for iOS 15 code paths
- Requires maintaining GCD/completion-based networking
- Introduces subtle behavioral differences between OS versions

**Use lower Swift version (5.9 or 5.10):**

Rejected because:
- Loses complete concurrency checking
- Can't use `@Observable` macro
- Requires manual Sendable conformances
- Data race safety becomes runtime issue instead of compile-time guarantee

**Support macOS 13+ for wider compatibility:**

Rejected because:
- CloudKit async APIs stabilized in macOS 13, but Swift 6 migration benefits justify newer requirement
- The library is designed for modern app development, not legacy system support
- Security-critical code benefits from latest framework improvements

## Migration Path

For projects on older platforms:

**Option 1: Update to latest platforms**
```swift
// In your app's Package.swift or Xcode project settings
platforms: [
    .iOS(.v26),
    .macOS(.v26),
]
```

**Option 2: Fork and backport**
- Fork the repository
- Lower platform requirements
- Replace async CloudKit calls with completion handlers
- Add manual Sendable conformances
- Add availability guards around modern APIs

Note: Backporting loses the safety guarantees and simplicity that motivated the original platform choice.

**Option 3: Vendor the concept**
- Implement the core pattern (CloudKit + Keychain caching) directly in your app
- Adapt to your specific platform requirements
- Maintain backward compatibility as needed

## See Also

- [Architecture](Architecture.md) — Actor-based concurrency model
- [KeychainStorage](KeychainStorage.md) — Keychain Security framework usage
