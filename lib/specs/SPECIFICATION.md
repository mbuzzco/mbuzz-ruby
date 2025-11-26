# mbuzz Ruby Gem - Technical Specification

**Version**: 1.0.0
**Created**: 2025-11-17
**Status**: Ready for Implementation

---

## Overview

A minimal, framework-agnostic Ruby gem for server-side multi-touch attribution tracking. The gem acts as a lightweight client wrapper that captures tracking events and sends them to the mbuzz SaaS API.

**Design Philosophy**: Inspired by Segment's analytics-ruby - simple class methods with named parameters, zero dependencies, and silent error handling.

**Primary Framework**: Rails (with expansion to Sinatra, Hanami, and other Ruby frameworks in future versions)

**Gem Name**: `mbuzz`
**Backend API**: Rails application at `mbuzz.co/api`

---

## System Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│  CLIENT APPLICATION (Rails, Sinatra, etc.)                  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  mbuzz Gem (Client Library)                            │ │
│  │                                                         │ │
│  │  Mbuzz.track(user_id: 1, event: 'Signup')             │ │
│  │  Mbuzz.identify(user_id: 1, traits: {...})            │ │
│  │  Mbuzz.alias(user_id: 1, previous_id: 'abc')          │ │
│  └────────────────────┬───────────────────────────────────┘ │
│                       │                                      │
└───────────────────────┼──────────────────────────────────────┘
                        │ HTTP/JSON
                        │ Bearer Token Auth
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  MBUZZ BACKEND (Rails at mbuzz.co/api)                      │
│                                                              │
│  POST /api/v1/events                                        │
│  GET  /api/v1/validate                                      │
│  GET  /api/v1/health                                        │
│                                                              │
│  Services:                                                   │
│  - ApiKeys::AuthenticationService                           │
│  - Events::IngestionService                                 │
│  - Events::ProcessingService (async via Solid Queue)        │
│  - Events::ValidationService                                │
│  - Events::EnrichmentService                                │
│  - Visitors::IdentificationService                          │
│  - Visitors::LookupService                                  │
│  - Sessions::IdentificationService                          │
│  - Sessions::TrackingService                                │
│  - Sessions::UtmCaptureService                              │
│  - Sessions::ChannelAttributionService                      │
│                                                              │
│  Returns Set-Cookie headers for visitor/session tracking    │
└─────────────────────────────────────────────────────────────┘
```

### Gem Responsibilities

**Capture**:
- Request context (URL, referrer, cookies, user agent)
- Generate visitor IDs if not present in cookies
- Build event payloads

**Send**:
- HTTP POST requests to `https://mbuzz.co/api/v1/events`
- Bearer token authentication
- Batch event submission (array of events)

**Integrate**:
- Forward Set-Cookie headers from API response
- Provide Rails middleware for automatic page view tracking
- Expose controller helpers for visitor ID access

**Resilience**:
- Handle errors gracefully (never raise exceptions)
- Log failures in debug mode
- Return boolean success indicators

### Backend Responsibilities

The mbuzz Rails backend (already implemented at mbuzz.co) handles:

**Authentication**:
- `ApiKeys::AuthenticationService` - Validates Bearer tokens
- `ApiKeys::RateLimiterService` - Enforces rate limits per account

**Event Processing**:
- `Events::IngestionService` - Accepts batch of events, validates, enqueues
- `Events::ValidationService` - Schema validation
- `Events::EnrichmentService` - Adds request metadata (URL, referrer, user agent)
- `Events::ProcessingService` - Async processing via Solid Queue jobs

**Visitor & Session Management**:
- `Visitors::IdentificationService` - Generates visitor IDs, manages cookies
- `Visitors::LookupService` - Find or create visitor records
- `Sessions::IdentificationService` - Manages session lifecycle
- `Sessions::TrackingService` - Creates/updates sessions
- `Sessions::UtmCaptureService` - Extracts UTM parameters from URLs
- `Sessions::ChannelAttributionService` - Derives channel from UTM/referrer

**Response**:
- Returns 202 Accepted for successful ingestion
- Returns Set-Cookie headers for `_mbuzz_vid` and `_mbuzz_sid`
- Returns accepted/rejected counts

---

## Gem Structure

```
mbuzz-ruby/
├── lib/
│   ├── mbuzz.rb                      # Main module & public API
│   └── mbuzz/
│       ├── version.rb                # Gem version (1.0.0)
│       ├── configuration.rb          # Config management
│       ├── client.rb                 # Core API (track, identify, alias)
│       ├── request_context.rb        # Thread-safe request capture
│       ├── api.rb                    # HTTP client (net/http)
│       ├── visitor/
│       │   └── identifier.rb         # Visitor ID generation
│       ├── middleware/
│       │   └── tracking.rb           # Rack middleware
│       ├── controller_helpers.rb     # Rails helpers
│       └── railtie.rb                # Rails integration
├── test/                             # Minitest test suite
├── mbuzz.gemspec
├── README.md
├── SPECIFICATION.md
├── CHANGELOG.md
└── LICENSE.txt
```

---

## Public API

### Mbuzz Module

The main namespace exposing three core methods:

#### Mbuzz.configure

Configure the gem with API credentials and options.

**Required Configuration**:
- `api_key` - Format: `sk_{environment}_{random}` (from mbuzz.co dashboard)

**Optional Configuration**:
- `api_url` - Defaults to `https://mbuzz.co/api/v1`
- `enabled` - Defaults to `true` (set `false` in test environment)
- `debug` - Defaults to `false` (enables verbose logging)
- `timeout` - Defaults to `5` seconds for HTTP requests

#### Mbuzz.track

Track events (page views, conversions, custom events).

**Parameters**:
- `user_id` - Database user ID (required if no anonymous_id)
- `anonymous_id` - Visitor ID from cookies (required if no user_id)
- `event` - Event name string (required)
- `properties` - Hash of event metadata (optional)
- `timestamp` - When event occurred (optional, defaults to now)

**Returns**:
- Success: `{ success: true, event_id: "evt_abc123" }`
- Failure: `false`

**Example**:
```ruby
result = Mbuzz::Client.track(
  visitor_id: "abc123",
  event_type: "page_view",
  properties: { url: "https://example.com" }
)

if result[:success]
  puts "Event tracked: #{result[:event_id]}"
end
```

**Backend Processing**: Events sent to `POST https://mbuzz.co/api/v1/events`, validated, enriched, and processed synchronously. Returns event ID with `evt_` prefix.

#### Mbuzz.identify

Associate traits with a user ID.

**Parameters**:
- `user_id` - Required
- `traits` - Hash of user attributes (email, name, plan, etc.)
- `timestamp` - Optional

**Returns**: `true` on success, `false` on failure

**Use Cases**:
- On signup (link user_id to visitor)
- When user attributes change
- On login (to refresh traits)

#### Mbuzz.alias

Link an anonymous visitor ID to a known user ID.

**Parameters**:
- `user_id` - The known user ID (required)
- `previous_id` - The anonymous visitor ID (required)

**Returns**: `true` on success, `false` on failure

**Use Case**: Connect pre-signup anonymous behavior to user account after registration.

---

## Service Objects

The gem uses a clean service object architecture:

### Mbuzz::Configuration

Manages gem configuration with validation.

**Responsibilities**:
- Store configuration values
- Validate required fields (API key)
- Provide defaults (`api_url` defaults to `https://mbuzz.co/api/v1`)
- Thread-safe access

### Mbuzz::Client

Orchestrates tracking calls.

**Responsibilities**:
- Validate parameters (user_id/anonymous_id present, event name required)
- Build event payloads
- Delegate HTTP calls to `Mbuzz::Api`
- Handle all errors gracefully
- Return result hash on success, `false` on failure
- Log failures in debug mode

**Public Methods**:
- `track(...)` - Track an event, returns `{ success: true, event_id: "evt_..." }` or `false`
- `identify(...)` - Identify a user, returns `true` or `false`
- `alias(...)` - Link visitor to user, returns `true` or `false`
- `conversion(...)` - Track conversion with attribution, returns `{ success: true, conversion_id: "conv_...", attribution: {...} }` or `false`

### Mbuzz::Api

HTTP client for communicating with mbuzz backend at mbuzz.co/api.

**Responsibilities**:
- Send POST requests to `https://mbuzz.co/api/v1/events`
- Add `Authorization: Bearer {api_key}` header
- Add `Content-Type: application/json` header
- Add `User-Agent: mbuzz-ruby/{version}` header
- Handle HTTP errors (4xx, 5xx) gracefully
- Handle network errors (timeout, connection refused)
- Return parsed response or boolean depending on method

**Public Methods**:
- `post(path, payload)` - Returns `true`/`false` (for identify, alias)
- `post_with_response(path, payload)` - Returns parsed JSON hash or `nil` (for track, conversion)

**Implementation**: Uses Ruby stdlib `net/http` only (zero external dependencies)

**Error Handling**: All errors caught, logged, but never raised

### Mbuzz::RequestContext

Thread-safe request/response storage.

**Responsibilities**:
- Store current request in thread-local variable
- Provide access to URL, referrer, user agent
- Clean up after request completes
- Work safely in multi-threaded environments (Puma, etc.)

**Pattern**: Thread-local storage with ensure block cleanup

**Public Methods**:
- `with_context(request:) { ... }` - Store request for block execution
- `current` - Get current request context (or nil)

**Instance Methods**:
- `url` - Current request URL
- `referrer` - HTTP Referer header
- `user_agent` - User-Agent header

### Mbuzz::Visitor::Identifier

Generates unique visitor IDs.

**Responsibilities**:
- Generate cryptographically secure random IDs
- Format: 64-character hex string (32 bytes from `SecureRandom`)

**Public Methods**:
- `generate` - Returns new visitor ID

**Note**: Backend's `Visitors::IdentificationService` also generates visitor IDs if client doesn't provide one. The gem generates them proactively to ensure consistent visitor tracking.

### Mbuzz::Middleware::Tracking

Rack middleware for automatic tracking.

**Responsibilities**:
- Capture request context in thread-local storage
- Track page views automatically for GET requests
- Filter out asset requests (JS, CSS, images)
- Clean up context after request completes
- Forward Set-Cookie headers from backend

**Integration**: Auto-installed via `Mbuzz::Railtie` in Rails apps

### Mbuzz::ControllerHelpers

Rails controller helper methods.

**Provides**:
- `mbuzz_visitor_id` - Get or generate visitor ID from cookies

**Usage**: Automatically included in all Rails controllers via Railtie

### Mbuzz::Railtie

Automatic Rails integration.

**Responsibilities**:
- Insert `Mbuzz::Middleware::Tracking` into Rack stack
- Include `Mbuzz::ControllerHelpers` in ActionController::Base
- Configure sensible defaults for Rails environment

---

## Backend Integration Points

### API Endpoints

**POST https://mbuzz.co/api/v1/events**
- Accepts: `{ events: [{ event_type, user_id, anonymous_id, timestamp, properties }] }`
- Returns: `{ accepted: 1, rejected: [] }` with 202 Accepted status
- Processing: `Events::IngestionService` → `Events::ValidationService` → `Events::ProcessingJob`

**GET https://mbuzz.co/api/v1/validate**
- Validates API key
- Returns account info if valid
- Used for testing gem configuration

**GET https://mbuzz.co/api/v1/health**
- Health check endpoint
- Returns 200 OK if backend is healthy

### Cookie Management

**Visitor Cookie** (`_mbuzz_vid`):
- Generated by gem's `Mbuzz::Visitor::Identifier` OR backend's `Visitors::IdentificationService`
- Lifetime: 1 year
- Format: 64-character hex string
- Set via `Set-Cookie` header from backend response

**Session Cookie** (`_mbuzz_sid`):
- Generated by backend's `Sessions::IdentificationService`
- Lifetime: 30 minutes
- Format: Random hex string
- Set via `Set-Cookie` header from backend response

**Gem Responsibility**: Forward `Set-Cookie` headers from API response to client response

### Event Enrichment Flow

1. **Client**: Gem captures request context (URL, referrer, user agent)
2. **Client**: Gem sends event payload to `https://mbuzz.co/api/v1/events`
3. **Backend**: `Events::EnrichmentService` adds additional metadata
4. **Backend**: `Events::ValidationService` validates schema
5. **Backend**: `Events::ProcessingJob` processes asynchronously
6. **Backend**: `Sessions::UtmCaptureService` extracts UTM parameters
7. **Backend**: `Sessions::ChannelAttributionService` derives channel

---

## Error Handling Philosophy

**Never raise exceptions to user code** - All errors are caught and logged.

**Error Categories**:
1. Configuration errors (missing API key)
2. Validation errors (missing required parameters)
3. Network errors (timeout, connection refused)
4. API errors (4xx, 5xx responses)

**Handling Strategy**:
- All public methods return `true` on success, `false` on failure
- Errors logged to `Rails.logger` (if available)
- In debug mode, print to STDERR
- Silent otherwise

**Rationale**: Tracking should never break the application.

---

## Features

### Phase 1 (MVP - This Gem)

**Core Tracking**:
- ✅ Track events with `Mbuzz.track`
- ✅ Identify users with `Mbuzz.identify`
- ✅ Alias visitors with `Mbuzz.alias`

**Rails Integration**:
- ✅ Automatic middleware installation via Railtie
- ✅ Automatic page view tracking
- ✅ Controller helper for visitor ID (`mbuzz_visitor_id`)
- ✅ Thread-safe request context

**Technical**:
- ✅ Zero runtime dependencies
- ✅ Silent error handling
- ✅ Bearer token authentication
- ✅ Synchronous HTTP requests

### Phase 2 (Future)

**Performance**:
- Batching events (queue in memory, flush periodically)
- Retry logic with exponential backoff
- Circuit breaker pattern

**Framework Support**:
- Sinatra adapter
- Hanami adapter
- Plain Rack support

---

## Testing Strategy

### Unit Tests

Test individual components:
- Configuration validation
- Client parameter validation
- Event payload building
- Visitor ID generation
- Request context capture
- API client HTTP requests

### Integration Tests

Test Rails integration:
- Middleware automatically installed
- Page views tracked
- Controller helper works
- Cookies managed correctly
- Set-Cookie headers forwarded

### Test Mode

Special mode for testing user applications:
- Capture calls without sending to API
- Assert on tracked events
- Clear captured calls between tests

---

## Dependencies

**Runtime**: ZERO

Uses only Ruby standard library:
- `net/http` - HTTP client
- `json` - JSON encoding/decoding
- `securerandom` - Visitor ID generation
- `uri` - URL parsing

**Development**:
- `minitest` - Testing framework
- `rake` - Build tasks
- `bundler` - Dependency management

**No external gems required** - Keeps gem size small and avoids dependency conflicts.

---

## API Communication

### Authentication

**Method**: Bearer token in Authorization header
**Format**: `Authorization: Bearer sk_live_abc123...`
**Validation**: Backend's `ApiKeys::AuthenticationService` validates token

### Request Format

**Endpoint**: `POST https://mbuzz.co/api/v1/events`

**Headers**:
- `Authorization: Bearer {api_key}`
- `Content-Type: application/json`
- `User-Agent: mbuzz-ruby/{version}`

**Body**:
```json
{
  "events": [{
    "event_type": "Signup",
    "user_id": "123",
    "timestamp": "2025-11-17T10:30:00Z",
    "properties": {
      "url": "https://example.com/signup",
      "referrer": "https://google.com",
      "user_agent": "Mozilla/5.0...",
      "plan": "pro"
    }
  }]
}
```

### Response Format

**Success** (202 Accepted):
```json
{
  "accepted": 1,
  "rejected": [],
  "events": [
    {
      "id": "evt_abc123def456",
      "event_type": "Signup",
      "visitor_id": "65dabef8d611f332...",
      "session_id": "xyz789...",
      "status": "accepted"
    }
  ]
}
```

**Event ID Format**: Prefixed IDs with `evt_` prefix (e.g., `evt_abc123def456`). These IDs can be used to:
- Link events to conversions via the `event_id` parameter
- Debug and trace specific events
- Reference events in support requests

**Headers**:
```
Set-Cookie: _mbuzz_vid=abc123...; Max-Age=31536000; HttpOnly; Secure; SameSite=Lax
Set-Cookie: _mbuzz_sid=xyz789...; Max-Age=1800; HttpOnly; Secure; SameSite=Lax
```

**Gem Responsibility**: Forward these Set-Cookie headers to the client response.

---

## Comparison to Segment

| Feature | Segment | mbuzz |
|---------|---------|-------|
| API Style | `Analytics.track(...)` | `Mbuzz.track(...)` |
| Dependencies | Many (faraday, concurrent-ruby) | **Zero** |
| Size | ~2000 LOC | ~500 LOC |
| Focus | Multi-destination routing | Single destination |
| Batching | Yes | Phase 2 |
| Async | Yes (thread pool) | Phase 2 |
| Framework Support | Many | Rails (expanding) |
| Server-side | Yes | Yes |
| Attribution Focus | No | **Yes** |

**mbuzz advantages**:
- Smaller, simpler codebase
- Zero dependencies
- Purpose-built for multi-touch attribution
- Tight integration with mbuzz backend services

---

## Implementation Phases

### Phase 1: Core Functionality (v1.0) - This Gem

- Configuration management (`Mbuzz.configure`)
- Client API (`Mbuzz.track`, `identify`, `alias`)
- HTTP client with `net/http`
- Request context (thread-safe)
- Visitor identification
- Rails integration (middleware, helpers, railtie)
- Error handling (silent failures)
- Test suite (>95% coverage)
- Documentation (README, SPECIFICATION)

### Phase 2: Performance & Reliability

- Event batching and queuing
- Retry logic with exponential backoff
- Circuit breaker for API failures
- Metrics and instrumentation

### Phase 3: Framework Expansion

- Sinatra support
- Hanami support
- Generic Rack adapter

---

## Success Criteria

**Functional**:
- ✅ Track events from anywhere (controllers, jobs, models)
- ✅ Automatic page view tracking in Rails
- ✅ Anonymous visitor tracking with cookies
- ✅ User identification and aliasing
- ✅ Request context enrichment

**Technical**:
- ✅ Zero runtime dependencies
- ✅ Silent error handling (never raises)
- ✅ Thread-safe in multi-threaded environments
- ✅ Integrates with mbuzz backend services at mbuzz.co/api
- ✅ Comprehensive test coverage (>95%)

**User Experience**:
- ✅ Simple, Segment-like API
- ✅ Automatic Rails integration via Railtie
- ✅ Clear documentation with examples
- ✅ Graceful degradation (tracking failures don't break app)

---

## Version History

- **v1.0.0** - Initial release
  - Core tracking (track, identify, alias)
  - Rails integration (middleware, helpers)
  - Zero dependencies
  - Silent error handling
  - Integration with mbuzz backend at mbuzz.co/api

---

Built for mbuzz.co
