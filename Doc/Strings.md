# Centralized Strings

## Overview

All user-facing and developer-facing error messages are defined in `Strings.swift` using SwiftUI's `String(localized:defaultValue:comment:)` API. This centralizes message definitions, enables localization, and provides clear guidance on intended audiences.

## Key Design Decisions

### Why Centralize Strings

Error messages are defined in a single file rather than inline with error types:

```swift
// Centralized in Strings.swift:
enum Strings {
    enum FetchKeyError {
        static let networkUnavailable = String(
            localized: "fetch_key_error_network_unavailable",
            defaultValue: "Unable to fetch API key: Please check your internet connection and try again",
            comment: "User-facing error when a network failure blocks API key fetching."
        )
    }
}

// Used in FetchKeyError.swift:
public var errorDescription: String? {
    switch self {
    case .networkUnavailable:
        Strings.FetchKeyError.networkUnavailable
    }
}
```

**Benefits:**

1. **Single source of truth** — Messages aren't duplicated across error types, logging, and UI code
2. **Localization-ready** — All strings use the `localized:` parameter, making them discoverable by `extractLocStrings` and `.xcstrings` generation
3. **Comment-based guidance** — Comments distinguish user-facing vs developer-facing errors without code coupling
4. **Easy auditing** — All error messages are in one file, making it easy to review tone, grammar, and audience

Without centralization, messages would be scattered across `FetchKeyError`, `APIKeyReader`, and logging statements.

### Why Use String(localized:) Instead of NSLocalizedString

The library uses SwiftUI's `String(localized:)` instead of Foundation's `NSLocalizedString`:

```swift
// Modern (SwiftUI):
String(
    localized: "fetch_key_error_network_unavailable",
    defaultValue: "Unable to fetch API key: Please check your internet connection and try again",
    comment: "User-facing error when a network failure blocks API key fetching."
)

// Legacy (Foundation):
NSLocalizedString(
    "fetch_key_error_network_unavailable",
    value: "Unable to fetch API key: Please check your internet connection and try again",
    comment: "User-facing error when a network failure blocks API key fetching."
)
```

**Why the modern API?**

1. **String Catalog integration** — `String(localized:)` works natively with Xcode's `.xcstrings` catalogs
2. **Compile-time checking** — Xcode's build-time string extraction validates keys and comments
3. **Simpler syntax** — Named parameters (`localized:`, `defaultValue:`) are clearer than positional arguments
4. **SwiftUI alignment** — Matches the API used by `Text("localized_key")`

`NSLocalizedString` still works but is legacy API.

### Why Comments Specify Audience

Each string's comment identifies its intended audience:

```swift
// User-facing:
comment: "User-facing error when a network failure blocks API key fetching."

// Developer-facing:
comment: "Developer-facing error when required CloudKit field is absent or not a string."
```

**Why include this in comments?**

1. **UI decisions** — Developers know which errors to show in alerts vs log to diagnostics
2. **Localization priority** — Translators prioritize user-facing strings over developer-facing ones
3. **Tone guidance** — User-facing messages use friendly language; developer messages use technical terms

Example distinction:

| Error | Audience | Message |
|-------|----------|---------|
| `networkUnavailable` | User | "Please check your internet connection and try again" |
| `missingField` | Developer | "Developer Error: Invalid key configuration - missing %@" |

### Why Default Values Are Inline

Default values are provided directly in the `String(localized:)` call:

```swift
static let recordNotFound = String(
    localized: "fetch_key_error_record_not_found",
    defaultValue: "Developer Error: Invalid configuration. The requested key was not found.",
    comment: "Developer-facing error when a required API key record does not exist in CloudKit."
)
```

**Why not separate the default into a constant?**

- **Single definition** — The key, default, and comment are co-located
- **Xcode extraction** — `extractLocStrings` requires inline `defaultValue` for proper catalog generation
- **Readability** — Developers reading `Strings.swift` see the full message without jumping to another file

Separating the default would break Xcode's string catalog tooling.

### Why Use Nested Enums

Strings are organized into nested enums matching error types:

```swift
enum Strings {
    enum FetchKeyError {
        static let missingField = String(...)
        static let cloudKitError = String(...)
        // ...
    }
}
```

**Why nest by error type?**

- **Namespace scoping** — Avoids naming collisions (multiple types might have a `notFound` error)
- **Logical grouping** — All `FetchKeyError` strings are together
- **Easy discovery** — Autocomplete suggests relevant strings when typing `Strings.FetchKeyError.`

Without nesting, all strings would be in a flat `Strings` enum, making it hard to find the right message.

### Why Format Strings Use %@

Messages with dynamic values use `%@` placeholders:

```swift
static let missingField = String(
    localized: "fetch_key_error_missing_field",
    defaultValue: "Developer Error: Invalid key configuration - missing %@",
    comment: "Developer-facing error when required CloudKit field is absent or not a string."
)

// Used with:
String(format: Strings.FetchKeyError.missingField, fieldName)
```

**Why `%@` instead of string interpolation?**

String interpolation doesn't work with `String(localized:)` — the interpolated value would be baked into the localization key. Using `%@` allows:
- Localization systems to preserve placeholder positions
- Translators to reorder placeholders (e.g., "missing %@" → "%@ est manquant")
- Runtime substitution via `String(format:)`

### Why "Developer Error" Prefix

Developer-facing errors start with "Developer Error:":

```swift
defaultValue: "Developer Error: Invalid key configuration - missing %@"
```

**Rationale:**

1. **Triage guidance** — Support teams know to escalate these to engineering, not user support
2. **Production detection** — Automated monitoring can flag logs containing "Developer Error" as high-priority bugs
3. **User exclusion** — These messages should never be shown in UI to end users

User-facing errors omit the prefix:

```swift
defaultValue: "Unable to fetch API key: Please check your internet connection and try again"
```

## Localization Workflow

### Step 1: Extract Strings

Xcode automatically extracts strings into `.xcstrings` catalogs:

```bash
# Build project to generate/update Localizable.xcstrings
xcodebuild -exportLocalizations -localizationPath ./Localizations
```

### Step 2: Translate

Edit `Localizable.xcstrings` to add translations:

```json
{
  "fetch_key_error_network_unavailable": {
    "comment": "User-facing error when a network failure blocks API key fetching.",
    "extractionState": "manual",
    "localizations": {
      "en": {
        "stringUnit": {
          "state": "translated",
          "value": "Unable to fetch API key: Please check your internet connection and try again"
        }
      },
      "es": {
        "stringUnit": {
          "state": "translated",
          "value": "No se pudo obtener la clave API: Por favor verifica tu conexión a internet e inténtalo de nuevo"
        }
      },
      "fr": {
        "stringUnit": {
          "state": "translated",
          "value": "Impossible de récupérer la clé API : Veuillez vérifier votre connexion Internet et réessayer"
        }
      }
    }
  }
}
```

### Step 3: Runtime Selection

iOS/macOS automatically selects the appropriate translation based on device language:

```swift
// User's device language is Spanish:
let message = Strings.FetchKeyError.networkUnavailable
// → "No se pudo obtener la clave API: ..."
```

## String Key Naming Convention

| Key | Pattern | Example |
|-----|---------|---------|
| Error messages | `<error_type>_<case_name>` | `fetch_key_error_network_unavailable` |
| UI labels | `<feature>_<element>` | `api_key_picker_title` |
| Placeholders | `<context>_placeholder` | `search_key_placeholder` |

Snake_case is used to match Swift Package conventions and improve readability in `.xcstrings` files.

## See Also

- [ErrorHandling](ErrorHandling.md) — How strings are used in error types
- [Architecture](Architecture.md) — Overall design philosophy
