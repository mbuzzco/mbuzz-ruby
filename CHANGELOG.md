# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - 2026-01-09

### Breaking Changes

- **Session cookie removed** - SDK no longer sets or reads `_mbuzz_sid` cookie
- **Session ID generation removed** - Server handles all session resolution
- **`Mbuzz.session_id` removed** - Use server-side session resolution instead
- **`Mbuzz::Client.session()` removed** - Sessions are created server-side
- **`session_id` parameter removed from `Client.track()`** - Not needed with server-side resolution

### Added

- **Cross-device identity resolution** - New `identifier` parameter for linking sessions across devices
  - `Mbuzz.event("page_view", identifier: { email: "user@example.com" })`
  - `Mbuzz.conversion("purchase", identifier: { email: "user@example.com" })`
- **Conversion fingerprint fallback** - `ip` and `user_agent` parameters on `Client.conversion()`
  - When visitor_id is not found, server can find visitor via recent session with same fingerprint

### Changed

- **Simplified middleware** - Only manages visitor cookie (`_mbuzz_vid`), no session handling
- **Server-side session resolution** - All session creation and resolution happens on the API server
  - Enables true 30-minute sliding windows (vs fixed time buckets)
  - Eliminates duplicate visitor problem from concurrent Turbo/Hotwire requests
  - Better cross-device tracking with identity resolution

### Migration Guide

1. Remove any code that reads `Mbuzz.session_id` or `_mbuzz_sid` cookie
2. Remove any calls to `Mbuzz::Client.session()`
3. Ensure `ip` and `user_agent` are passed to track/conversion calls (handled automatically if using middleware)
4. Optionally add `identifier` parameter for cross-device tracking

## [0.6.8] - 2025-12-30

### Added

- **Server-side session resolution support** - SDK now forwards `ip` and `user_agent` to the API for server-side session identification
- `ip` and `user_agent` parameters on `Mbuzz::Client.track()`
- `RequestContext#ip` method with proxy header support (X-Forwarded-For, X-Real-IP)
- `Mbuzz.event` automatically extracts and forwards ip/user_agent from request context

### Technical Details

- IP extraction priority: `X-Forwarded-For` (first IP) > `X-Real-IP` > direct IP
- Enables accurate session tracking without client-side cookies
- Backwards compatible - ip/user_agent are optional parameters

## [0.6.0] - 2025-12-05

### Added

- **Path filtering in middleware** - Automatically skip tracking for:
  - Health check endpoints (`/up`, `/health`, `/healthz`, `/ping`)
  - Asset paths (`/assets`, `/packs`, `/rails/active_storage`)
  - WebSocket paths (`/cable`)
  - API paths (`/api`)
  - Static assets by extension (`.js`, `.css`, `.png`, `.woff2`, etc.)
- `skip_paths` configuration option - Add custom paths to skip
- `skip_extensions` configuration option - Add custom extensions to skip

### Fixed

- Health check requests no longer create sessions or consume API quota
- Static asset requests no longer pollute tracking data

### Usage

```ruby
Mbuzz.init(
  api_key: "sk_live_...",
  skip_paths: ["/admin", "/internal"],      # Optional: additional paths to skip
  skip_extensions: [".pdf", ".xml"]         # Optional: additional extensions to skip
)
```

## [0.5.0] - 2025-11-29

### Breaking Changes

- `Mbuzz.configure` replaced with `Mbuzz.init`
- `Mbuzz.track` renamed to `Mbuzz.event`
- `Mbuzz.alias` removed - merged into `Mbuzz.identify`
- `Mbuzz.identify` signature changed: positional user_id, keyword traits/visitor_id

### Added

- `Mbuzz.init(api_key:, ...)` - new configuration method
- `Mbuzz.event(event_type, **properties)` - cleaner event tracking
- Automatic visitor linking in `identify` when visitor_id available
- `enriched_properties` in RequestContext for URL/referrer auto-enrichment

### Removed

- `Mbuzz.configure` block syntax
- `Mbuzz.track` method
- `Mbuzz.alias` method
- `Mbuzz::Client::AliasRequest` class

## [0.2.0] - 2025-11-25

### BREAKING CHANGES

This release fixes critical bugs that prevented events from being tracked. You MUST update your code to use this version.

### Changed

- **BREAKING**: Renamed `event:` parameter to `event_type:` to match backend API
  - Before: `Mbuzz.track(event: 'Signup', user_id: 1)`
  - After: `Mbuzz.track(event_type: 'Signup', user_id: 1)`
  - Migration: Search/replace `event:` → `event_type:` in all `Mbuzz.track()` calls

- **BREAKING**: Changed timestamp format from Unix epoch to ISO8601
  - Before: Sent `1732550400` (integer)
  - After: Sends `"2025-11-25T10:30:00Z"` (ISO8601 string)
  - Migration: No action required - gem handles this automatically

### Fixed

- Events are now correctly formatted and accepted by backend
- Timestamps are now in UTC with ISO8601 format

## [0.1.0] - 2025-11-25

### Added

- Initial release
- Event tracking with `Mbuzz::Client.track()`
- User identification with `Mbuzz::Client.identify()`
- Visitor aliasing with `Mbuzz::Client.alias()`
- Automatic visitor and session management via middleware
- Rails integration via Railtie
- Controller helpers for convenient tracking
