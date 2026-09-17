# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.1] - 2026-09-17

### Fixed — the visitor's IP now reaches mbuzz on session create

- **`POST /api/v1/sessions` now carries `ip`.** The middleware already extracted the visitor's
  address — it is half of `device_fingerprint = SHA256(ip|user_agent)` — and then dropped it at
  three points on the way out: `Client.session` had no `ip:` keyword, `SessionRequest#payload`
  omitted it, and `Middleware::Tracking`'s own call site omitted it too. Events and conversions have
  always sent one; only sessions did not.
- **Why it matters.** mbuzz sends Meta's Conversions API `client_ip_address`, which Meta documents
  as **required** for website events, and a session with no address means the events resolved
  through it carry none either. Upgrading improves Event Match Quality for anyone using conversion
  feedback; it changes nothing else.
- **No API change.** `ip:` is an optional keyword on `Client.session` and both middlewares fill it
  automatically. Existing callers need no edit.

Found by the SDK integration harness rather than by unit tests: every layer was correct on its own,
and only a real request through a real app could tell the visitor's address from the app server's.

## [0.10.0] - 2026-09-08

### BREAKING — the page snippet is now required

- **A page response no longer sets the visitor cookie.** Only `POST /_mbuzz/session` mints, and the inline snippet in the README's "Full-page caching" section is what calls it. **Upgrading without adding that snippet stops tracking entirely** — no cookie is ever minted, so no visitor exists and every event is dropped.

### Fixed

- **A cached page no longer hands every visitor the same id.** The page response carried a `Set-Cookie`, and a full-page cache stored it and replayed it to everyone — so unrelated people merged into a single journey. Corruption rather than loss: every row still exists, each attributed to the wrong person, and nothing looks missing. The page path now uses only the cookie the browser already holds; the uncached session endpoint is the sole place a visitor is minted.

  Found by the cache harness at `sdk_integration_tests/scenarios/page_cache_test.rb`, and it could not have been found any other way: in isolation "reuse the cookie the browser presents" is correct — it is what lets a returning visitor keep their id. The bug exists only once a cache has handed one cookie to many people. The WordPress plugin reached the same conclusion first (`CookieBootstrap::CONTEXT_PAGE`).

## [0.9.0] - 2026-09-02

### Added

- **A dropped event or conversion now says so.** `Mbuzz.event` and `Mbuzz.conversion` return `false` when there is no `visitor_id` and no `user_id` — previously with no request, no log and no signal of any kind. That silence is what made the caching bug above invisible on a live account for a full day. They now warn at `Rails.logger.warn` (or stderr outside Rails), naming the dropped call and pointing at the session endpoint. Deliberately **not** gated behind `debug`: the people who hit this are precisely the ones not running in debug.
- **Attribution now survives a full-page cache.** A cached page is answered without entering the Rack stack, so the tracking middleware never ran, no visitor cookie was set, and every later event was dropped for having no one to attribute it to — silently, while the page rendered perfectly. `Mbuzz::Middleware::SessionEndpoint` answers `POST /_mbuzz/session`, a path caches don't store, and the server sets the cookie on that response. Mounted automatically in Rails; add it ahead of `Tracking` in Rack/Sinatra apps. See "Full-page caching" in the README for the one-time page snippet.

### Notes

- The visitor id is still never created or read in JavaScript. It stays `HttpOnly` and server-set, preserving its full two-year life — a cookie written by `document.cookie` is capped at 7 days under Safari's ITP, and 24 hours after an ad click.
- Inline the page snippet rather than serving it as a file: asset optimisers delay external scripts until first interaction, which would miss any visitor who lands and converts without clicking first.

## [0.8.2] - 2026-03-15

### Changed

- **Removed `api_url` from `init()` parameters** — the proxy URL (`https://api.mbuzz.co/api/v1`) is now hardcoded. This prevents accidental bypass of the edge ingest proxy. For development, `Mbuzz.config.api_url` can still be set directly after init.

## [0.8.1] - 2026-03-16

### Fixed

- **`event()` and `conversion()` now handle proxy-buffered responses gracefully** — when the edge proxy accepts a request but Rails is temporarily unreachable, the SDK returns `{ success: true }` with nil IDs instead of `false`. Data is safe in the proxy buffer and will be processed on recovery.

## [0.8.0] - 2026-03-13

### Changed

- **Default API URL updated to `https://api.mbuzz.co/api/v1`** — traffic now routes through the edge ingest proxy for improved reliability. The previous URL (`https://mbuzz.co/api/v1`) remains supported as a configurable fallback via `api_url`.

## [0.7.4] - 2026-02-17

### Fixed

- **`conversion()` now resolves `user_id` from context** — the `user_id: nil` parameter was shadowing `self.user_id`, preventing the identify → convert flow from working. `event()` was not affected.
- **`identify()` now stores `user_id` in context** — after a successful API call, `user_id` is written to `Current.user_id` and `request.env` so that subsequent `conversion()` calls in the same request can resolve it.

## [0.7.3] - 2026-02-02

### Breaking Changes

- **Session cookie removed** — `_mbuzz_sid` cookie is no longer set or read. Sessions are fully server-side.
- **`SESSION_COOKIE_NAME` and `SESSION_COOKIE_MAX_AGE` constants removed** from `Mbuzz` module.

### Added

- **Navigation-aware session creation** — middleware now gates `POST /sessions` on real page navigations using browser-enforced `Sec-Fetch-*` headers (whitelist), with a framework-specific blacklist fallback for older browsers and bots.
  - Turbo Frame, htmx, Unpoly, and XHR sub-requests no longer create spurious sessions.
  - Prefetches and iframe loads are correctly filtered out.
- New public methods on `Mbuzz::Middleware::Tracking`: `should_create_session?`, `sec_fetch_headers?`, `page_navigation?`, `framework_sub_request?`

### Migration Guide

1. Remove any code that reads or depends on the `_mbuzz_sid` cookie.
2. Remove references to `Mbuzz::SESSION_COOKIE_NAME` or `Mbuzz::SESSION_COOKIE_MAX_AGE`.
3. Visitor cookie (`_mbuzz_vid`) is unaffected — still set on every request.

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
