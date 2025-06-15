# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

APIKeyReader is a Swift Package Manager library for iOS/macOS that manages API keys by fetching them from CloudKit and caching them locally. It uses modern Swift concurrency features and requires Swift 6.0+.

## Development Commands

### Code Formatting
```bash
./formatcode.sh
# Or manually: swiftformat . --indent 4 --swiftversion 6.0 --disable wrapMultilineStatementBraces
```

### Building
```bash
swift build
```

### Testing
```bash
swift test
```

## Architecture

### Core Components

1. **APIKeyReader (Actor)** - Main entry point, manages key fetching and caching
   - Singleton pattern with shared instance
   - Requires configuration with CloudKit container ID
   - Implements task deduplication to prevent duplicate fetches

2. **CloudKitKeyProvider** - Fetches keys from CloudKit
   - Located in `Sources/APIKeyReader/Contains/CloudKitKeyProvider/`
   - Handles CloudKit queries and error mapping

3. **LocalStorage** - Caches keys with expiration
   - Located in `Sources/APIKeyReader/Contains/LocalStorage/`
   - Implements automatic cleanup of expired keys

### Key Design Patterns

- **Actor-based Concurrency**: Thread-safe access to shared state
- **Error Resilience**: Returns expired cached keys if fresh fetch fails
- **Type Safety**: Uses `APIKeyName` enum for compile-time key validation
- **Task Deduplication**: Prevents redundant network requests for same key

### Error Handling

The library defines specific error types:
- `LoadError`: CloudKit fetch failures with detailed error types
- `FetchKeyError`: Configuration and invalid key errors

### Usage Flow

1. Configure APIKeyReader with CloudKit container ID
2. Request key using type-safe `APIKeyName`
3. Library checks local cache first
4. If expired/missing, fetches from CloudKit
5. Falls back to expired cache if network fails

## Important Notes

- Always run `swiftformat` before committing changes
- The library supports iOS 18+ and macOS 15+
- TestApp directory contains a sample implementation
- All CloudKit operations are abstracted through the provider pattern