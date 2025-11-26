# Event IDs in API Response - Technical Specification

**Version**: 1.1.0
**Created**: 2025-11-26
**Status**: Ready for Implementation
**Breaking Change**: Yes (return type change for `track`)

---

## Overview

Update the Ruby SDK to return event IDs from the API response. This enables users to:
1. Link events to conversions via the `event_id` parameter
2. Debug and trace specific events
3. Reference events in support requests

---

## Breaking Change

### Before (v1.0)

```ruby
result = Mbuzz::Client.track(
  visitor_id: "abc123",
  event_type: "page_view",
  properties: { url: "https://example.com" }
)
# => true or false
```

### After (v1.1)

```ruby
result = Mbuzz::Client.track(
  visitor_id: "abc123",
  event_type: "page_view",
  properties: { url: "https://example.com" }
)
# => { success: true, event_id: "evt_abc123" } or false
```

### Migration Guide

**Existing code** (still works):
```ruby
# Boolean check still works because Hash is truthy
if Mbuzz::Client.track(visitor_id: vid, event_type: "page_view")
  puts "Event tracked"
end
```

**New code** (recommended):
```ruby
result = Mbuzz::Client.track(visitor_id: vid, event_type: "page_view")
if result && result[:success]
  puts "Event ID: #{result[:event_id]}"
end

# Or with safe navigation
if result&.dig(:success)
  event_id = result[:event_id]
end
```

---

## API Changes

### Backend Response Format

The Events API now returns event details in the response:

**POST /api/v1/events**

```json
{
  "accepted": 1,
  "rejected": [],
  "events": [
    {
      "id": "evt_abc123def456",
      "event_type": "page_view",
      "visitor_id": "65dabef8d611f332d5bb88f5d6870c733d89f962594575b66f0e1de1ede1ebf0",
      "session_id": "sess_xyz789",
      "status": "accepted"
    }
  ]
}
```

### Event ID Format

- **Prefix**: `evt_`
- **Entropy**: 128-bit (32 hex characters after prefix)
- **Example**: `evt_abc123def456789...`
- **Security**: Account-scoped, not guessable

---

## Implementation

### Mbuzz::Api Changes

Add new method to return parsed response:

```ruby
# lib/mbuzz/api.rb

def self.post_with_response(path, payload)
  return nil unless enabled_and_configured?

  response = http_client(path).request(build_request(path, payload))
  return nil unless success?(response)

  JSON.parse(response.body)
rescue ConfigurationError, Net::ReadTimeout, Net::OpenTimeout, Net::HTTPError, JSON::ParserError => e
  log_error("#{e.class}: #{e.message}")
  nil
end
```

### Mbuzz::Client Changes

Update `track` to use new API method and return event ID:

```ruby
# lib/mbuzz/client.rb

def self.track(user_id: nil, visitor_id: nil, event_type:, properties: {})
  return false unless valid_event_type?(event_type)
  return false unless valid_properties?(properties)
  return false unless valid_identifier?(user_id, visitor_id)

  event = {
    user_id: user_id,
    visitor_id: visitor_id,
    event_type: event_type,
    properties: properties,
    timestamp: Time.now.utc.iso8601
  }.compact

  response = Api.post_with_response(EVENTS_PATH, { events: [event] })
  return false unless response

  event_data = response["events"]&.first
  return false unless event_data

  {
    success: true,
    event_id: event_data["id"],
    event_type: event_data["event_type"],
    visitor_id: event_data["visitor_id"],
    session_id: event_data["session_id"]
  }
rescue StandardError => e
  log_error("Track error: #{e.message}")
  false
end

private_class_method def self.log_error(message)
  warn "[mbuzz] #{message}" if Mbuzz.config.debug
end
```

---

## Use Cases

### 1. Link Event to Conversion

```ruby
# Track the purchase event
result = Mbuzz::Client.track(
  visitor_id: mbuzz_visitor_id,
  event_type: "purchase_completed",
  properties: { order_id: order.id, total: order.total }
)

# Create conversion linked to the event
if result[:success]
  Mbuzz::Client.conversion(
    visitor_id: mbuzz_visitor_id,
    conversion_type: "purchase",
    revenue: order.total,
    event_id: result[:event_id]  # Link to triggering event
  )
end
```

### 2. Debug Event Flow

```ruby
result = Mbuzz::Client.track(
  visitor_id: visitor_id,
  event_type: "signup",
  properties: { plan: "pro" }
)

if result[:success]
  Rails.logger.info "Tracked signup: #{result[:event_id]} for visitor #{result[:visitor_id]}"
else
  Rails.logger.warn "Failed to track signup for visitor #{visitor_id}"
end
```

### 3. Store Event References

```ruby
class Order < ApplicationRecord
  def track_purchase
    result = Mbuzz::Client.track(
      visitor_id: user.mbuzz_visitor_id,
      event_type: "purchase",
      properties: { order_id: id, total: total }
    )

    update!(mbuzz_event_id: result[:event_id]) if result[:success]
  end
end
```

---

## Testing

### Unit Tests

```ruby
class ClientTrackTest < Minitest::Test
  def test_track_returns_event_id_on_success
    stub_successful_events_response

    result = Mbuzz::Client.track(
      visitor_id: "abc123",
      event_type: "page_view"
    )

    assert result[:success]
    assert result[:event_id].start_with?("evt_")
  end

  def test_track_returns_false_on_validation_failure
    result = Mbuzz::Client.track(
      visitor_id: nil,
      event_type: "page_view"
    )

    assert_equal false, result
  end

  def test_track_returns_false_on_api_failure
    stub_failed_events_response

    result = Mbuzz::Client.track(
      visitor_id: "abc123",
      event_type: "page_view"
    )

    assert_equal false, result
  end

  def test_track_still_truthy_for_boolean_checks
    stub_successful_events_response

    result = Mbuzz::Client.track(
      visitor_id: "abc123",
      event_type: "page_view"
    )

    # Backwards compatibility: result is truthy
    assert result
    if result
      assert true, "Boolean check still works"
    end
  end
end
```

### Integration Test

```ruby
def test_track_and_conversion_with_event_id
  visitor_id = "test_#{SecureRandom.hex(8)}"

  # Track event
  track_result = Mbuzz::Client.track(
    visitor_id: visitor_id,
    event_type: "signup",
    properties: { plan: "pro" }
  )

  assert track_result[:success]
  assert track_result[:event_id].present?

  # Create conversion linked to event
  conv_result = Mbuzz::Client.conversion(
    visitor_id: visitor_id,
    conversion_type: "signup",
    event_id: track_result[:event_id]
  )

  assert conv_result[:success]
  assert conv_result[:conversion_id].present?
end
```

---

## Backwards Compatibility

The change is **mostly backwards compatible**:

| Pattern | v1.0 | v1.1 | Works? |
|---------|------|------|--------|
| `if Mbuzz::Client.track(...)` | `true` | `{ success: true, ... }` | ✅ Yes (Hash is truthy) |
| `result == true` | `true` | `{ ... }` | ❌ No |
| `result[:event_id]` | Error | `"evt_..."` | ✅ Yes (new feature) |
| `!result` | `false` | `false` | ✅ Yes |

**Recommendation**: Update code to check `result[:success]` instead of `result == true`.

---

## Version Bump

This is a minor version bump (1.0 → 1.1) because:
- Return type change could break `result == true` checks
- New functionality added (event IDs)
- Existing boolean checks still work (Hash is truthy)

---

## Success Criteria

- [ ] `Api.post_with_response` method implemented
- [ ] `Client.track` returns hash with event_id on success
- [ ] `Client.track` returns `false` on failure (unchanged)
- [ ] Boolean checks still work (backwards compatible)
- [ ] Unit tests cover all cases
- [ ] Integration test validates event_id linking to conversion
- [ ] CHANGELOG updated with breaking change note

---

Built for mbuzz.co
