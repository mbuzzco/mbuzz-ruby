# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
