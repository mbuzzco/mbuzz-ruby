# Conversions API - Technical Specification

**Version**: 1.1.0
**Created**: 2025-11-26
**Updated**: 2025-11-26
**Status**: Ready for Implementation

---

## Overview

Add conversion tracking to the mbuzz Ruby gem. Conversions are the critical attribution endpoint - they trigger the attribution calculation that credits marketing touchpoints for revenue.

**Purpose**: Allow Ruby SDK users to track conversions (purchases, signups, upgrades) and retrieve attribution data showing which marketing channels drove the conversion.

---

## API Design

### Mbuzz::Client.conversion

Track a conversion event and trigger attribution calculation.

**Method Signature**:
```ruby
Mbuzz::Client.conversion(
  event_id: nil,         # Identifier option A - Link to specific event
  visitor_id: nil,       # Identifier option B - Visitor ID (uses most recent session)
  conversion_type:,      # Required - Type: "purchase", "signup", "upgrade", etc.
  revenue: nil,          # Optional - Revenue amount (numeric)
  currency: "USD",       # Optional - Currency code (default: USD)
  properties: {}         # Optional - Additional metadata
)
```

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `event_id` | String | One of event_id/visitor_id | Prefixed event ID (`evt_*`) - visitor/session derived from event |
| `visitor_id` | String | One of event_id/visitor_id | Raw visitor ID (64-char hex from `_mbuzz_vid`) - uses most recent session |
| `conversion_type` | String | Yes | Type of conversion (e.g., "purchase", "signup") |
| `revenue` | Numeric | No | Revenue amount for ROI calculations |
| `currency` | String | No | ISO 4217 currency code (default: "USD") |
| `properties` | Hash | No | Additional conversion metadata |

**Identifier Resolution**:
- If `event_id` provided: Use event's visitor and session (most precise)
- If only `visitor_id` provided: Look up visitor, use most recent session
- If both provided: `event_id` takes precedence
- If neither provided: Return `false` (validation error)

**Returns**:
- Success: `{ success: true, conversion_id: "conv_abc123", attribution: {...} }`
- Failure: `false`

**Example Usage**:
```ruby
# Option A: Event-based (recommended for precise attribution)
track_result = Mbuzz::Client.track(
  visitor_id: mbuzz_visitor_id,
  event_type: 'checkout_completed',
  properties: { order_id: order.id }
)

if track_result[:success]
  result = Mbuzz::Client.conversion(
    event_id: track_result[:event_id],
    conversion_type: 'purchase',
    revenue: order.total
  )
end

# Option B: Visitor-based (simpler, for direct conversions)
result = Mbuzz::Client.conversion(
  visitor_id: mbuzz_visitor_id,
  conversion_type: 'purchase',
  revenue: 99.00,
  properties: { plan: 'pro' }
)

# Access attribution data
if result[:success]
  puts "Conversion ID: #{result[:conversion_id]}"

  result[:attribution][:models].each do |model_name, credits|
    puts "#{model_name}:"
    credits.each do |credit|
      puts "  #{credit[:channel]}: #{(credit[:credit] * 100).round(1)}%"
    end
  end
end
```

---

## When to Use Each Approach

| Approach | Use Case |
|----------|----------|
| **Event-based** (`event_id`) | Tie conversion to specific action (checkout button click, form submit) |
| **Visitor-based** (`visitor_id`) | Direct conversions, offline imports, webhook integrations, simpler SDK usage |

**Event-based advantages**:
- Most precise - conversion tied to exact moment in journey
- Event has full context (properties, timestamp)
- Better for debugging and analysis

**Visitor-based advantages**:
- Simpler - don't need to track an event first
- Works for offline/imported conversions
- Better for direct purchase flows (land → buy immediately)

---

## Backend Integration

### API Endpoint

**POST https://mbuzz.co/api/v1/conversions**

**Request Headers**:
```
Authorization: Bearer sk_live_abc123...
Content-Type: application/json
User-Agent: mbuzz-ruby/1.0.0
```

**Request Body (Event-based)**:
```json
{
  "conversion": {
    "event_id": "evt_abc123def456",
    "conversion_type": "purchase",
    "revenue": 99.00,
    "properties": {
      "plan": "pro"
    }
  }
}
```

**Request Body (Visitor-based)**:
```json
{
  "conversion": {
    "visitor_id": "65dabef8d611f332d5bb88f5d6870c733d89f962594575b66f0e1de1ede1ebf0",
    "conversion_type": "purchase",
    "revenue": 99.00,
    "properties": {
      "plan": "pro"
    }
  }
}
```

**Success Response** (201 Created):
```json
{
  "id": "conv_xyz789",
  "visitor_id": "vis_abc123",
  "conversion_type": "purchase",
  "revenue": "99.0",
  "converted_at": "2025-11-26T10:30:00Z",
  "attribution": {
    "lookback_days": 30,
    "sessions_analyzed": 3,
    "models": {
      "first_touch": [
        {
          "session_id": "sess_111",
          "channel": "organic_search",
          "credit": 1.0,
          "revenue_credit": "99.0"
        }
      ],
      "last_touch": [
        {
          "session_id": "sess_333",
          "channel": "email",
          "credit": 1.0,
          "revenue_credit": "99.0"
        }
      ],
      "linear": [
        {
          "session_id": "sess_111",
          "channel": "organic_search",
          "credit": 0.333,
          "revenue_credit": "33.0"
        },
        {
          "session_id": "sess_222",
          "channel": "paid_social",
          "credit": 0.333,
          "revenue_credit": "33.0"
        },
        {
          "session_id": "sess_333",
          "channel": "email",
          "credit": 0.334,
          "revenue_credit": "33.0"
        }
      ]
    }
  }
}
```

**Error Response** (422 Unprocessable Entity):
```json
{
  "errors": ["event_id or visitor_id is required"]
}
```

```json
{
  "errors": ["Visitor not found"]
}
```

---

## Attribution Models

The backend calculates attribution across all active models for the account:

### Implemented Models

| Model | Description | Credit Distribution |
|-------|-------------|---------------------|
| `first_touch` | First session gets all credit | 100% to first session |
| `last_touch` | Last session gets all credit | 100% to last session |
| `linear` | Equal credit to all sessions | Even split across sessions |

### Future Models (Not Yet Implemented)

| Model | Description |
|-------|-------------|
| `time_decay` | More recent sessions get more credit |
| `u_shaped` | First and last get 40% each, middle splits 20% |
| `w_shaped` | First, lead creation, last get 30% each, rest splits 10% |
| `participation` | All sessions get 100% (over-counts to show participation) |

---

## Implementation Details

### Client Implementation

```ruby
# lib/mbuzz/client.rb

def self.conversion(event_id: nil, visitor_id: nil, conversion_type:, revenue: nil, currency: "USD", properties: {})
  ConversionRequest.new(event_id, visitor_id, conversion_type, revenue, currency, properties).call
end
```

### ConversionRequest Implementation

```ruby
# lib/mbuzz/client/conversion_request.rb

module Mbuzz
  class Client
    class ConversionRequest
      def initialize(event_id, visitor_id, conversion_type, revenue, currency, properties)
        @event_id = event_id
        @visitor_id = visitor_id
        @conversion_type = conversion_type
        @revenue = revenue
        @currency = currency
        @properties = properties
      end

      def call
        return false unless valid?

        response = Api.post_with_response(CONVERSIONS_PATH, payload)
        return false unless response

        {
          success: true,
          conversion_id: response["id"],
          attribution: symbolize_attribution(response["attribution"])
        }
      end

      private

      def valid?
        has_identifier? && present?(@conversion_type) && hash?(@properties)
      end

      def has_identifier?
        present?(@event_id) || present?(@visitor_id)
      end

      def payload
        {
          conversion: base_payload
            .tap { |p| p[:event_id] = @event_id if @event_id }
            .tap { |p| p[:visitor_id] = @visitor_id if @visitor_id }
            .tap { |p| p[:revenue] = @revenue if @revenue }
        }
      end

      def base_payload
        {
          conversion_type: @conversion_type,
          currency: @currency,
          properties: @properties,
          timestamp: Time.now.utc.iso8601
        }
      end

      def symbolize_attribution(attr)
        return nil unless attr
        # Convert string keys to symbols for Ruby-friendly access
        attr.transform_keys(&:to_sym)
      end

      def present?(value) = value && !value.to_s.strip.empty?
      def hash?(value) = value.is_a?(Hash)
    end
  end
end
```

### Constants

```ruby
# lib/mbuzz.rb

CONVERSIONS_PATH = "/conversions"
```

---

## Validation Rules

### Client-Side Validation

| Field | Rule | Error Behavior |
|-------|------|----------------|
| `event_id` OR `visitor_id` | At least one required | Return `false` |
| `conversion_type` | Required, non-empty string | Return `false` |
| `revenue` | Optional, numeric if present | Return `false` if non-numeric |
| `properties` | Optional, must be Hash | Return `false` if not Hash |

### Backend Validation

| Field | Rule | Error Response |
|-------|------|----------------|
| `event_id` OR `visitor_id` | At least one required | 422 "event_id or visitor_id is required" |
| `event_id` | Must exist if provided | 422 "Event not found" |
| `visitor_id` | Must exist if provided | 422 "Visitor not found" |
| `conversion_type` | Non-empty string | 422 "conversion_type is required" |
| `revenue` | Numeric if present | 422 "Revenue must be numeric" |

---

## Error Handling

Following the gem's philosophy: **never raise exceptions**.

```ruby
# All errors return false
result = Mbuzz::Client.conversion(conversion_type: "purchase")
# => false (no identifier)

result = Mbuzz::Client.conversion(visitor_id: "abc", conversion_type: "")
# => false (empty conversion_type)

# Network errors return false
result = Mbuzz::Client.conversion(visitor_id: "abc", conversion_type: "purchase")
# => false (if network timeout)

# Success returns hash with data
result = Mbuzz::Client.conversion(visitor_id: "abc", conversion_type: "purchase")
# => { success: true, conversion_id: "conv_xyz", attribution: {...} }
```

---

## Testing

### Unit Tests

```ruby
# test/mbuzz/client/conversion_request_test.rb

class ConversionRequestTest < Minitest::Test
  # Identifier validation
  def test_requires_event_id_or_visitor_id
    result = Mbuzz::Client.conversion(
      conversion_type: "purchase"
    )
    assert_equal false, result
  end

  def test_accepts_event_id_only
    stub_successful_conversion_response

    result = Mbuzz::Client.conversion(
      event_id: "evt_abc123",
      conversion_type: "purchase"
    )

    assert result[:success]
  end

  def test_accepts_visitor_id_only
    stub_successful_conversion_response

    result = Mbuzz::Client.conversion(
      visitor_id: "65dabef8d611f332d5bb88f5d6870c733d89f962594575b66f0e1de1ede1ebf0",
      conversion_type: "purchase"
    )

    assert result[:success]
  end

  def test_accepts_both_identifiers
    stub_successful_conversion_response

    result = Mbuzz::Client.conversion(
      event_id: "evt_abc123",
      visitor_id: "65dabef8...",
      conversion_type: "purchase"
    )

    assert result[:success]
  end

  # Conversion type validation
  def test_requires_conversion_type
    result = Mbuzz::Client.conversion(
      visitor_id: "abc123",
      conversion_type: nil
    )
    assert_equal false, result
  end

  def test_rejects_empty_conversion_type
    result = Mbuzz::Client.conversion(
      visitor_id: "abc123",
      conversion_type: ""
    )
    assert_equal false, result
  end

  # Response handling
  def test_returns_conversion_id_on_success
    stub_successful_conversion_response

    result = Mbuzz::Client.conversion(
      event_id: "evt_abc123",
      conversion_type: "purchase"
    )

    assert result[:conversion_id].start_with?("conv_")
  end

  def test_returns_attribution_data
    stub_successful_conversion_response

    result = Mbuzz::Client.conversion(
      event_id: "evt_abc123",
      conversion_type: "purchase"
    )

    assert result[:attribution].is_a?(Hash)
    assert result[:attribution][:models].key?("first_touch")
  end
end
```

### Integration Tests (UAT)

```ruby
# Full attribution flow test
visitor_id = "uat_#{SecureRandom.hex(8)}"

# Create journey with 3 sessions
event_ids = []
3.times do |i|
  result = Mbuzz::Client.track(
    visitor_id: visitor_id,
    event_type: "page_view",
    properties: {
      session_id: "sess_#{i}_#{SecureRandom.hex(4)}",
      utm_source: ["google", "facebook", "newsletter"][i],
      utm_medium: ["organic", "paid", "email"][i]
    }
  )
  event_ids << result[:event_id] if result[:success]
end

# Test event-based conversion
result = Mbuzz::Client.conversion(
  event_id: event_ids.last,
  conversion_type: "purchase",
  revenue: 99.00
)

assert result[:success]
assert_equal 3, result[:attribution][:sessions_analyzed]

# Test visitor-based conversion
result2 = Mbuzz::Client.conversion(
  visitor_id: visitor_id,
  conversion_type: "upsell",
  revenue: 49.00
)

assert result2[:success]
```

---

## Usage Examples

### Rails Controller

```ruby
class CheckoutsController < ApplicationController
  def create
    @order = Order.create!(order_params)

    # Option A: Event-based (recommended)
    track_result = Mbuzz::Client.track(
      visitor_id: mbuzz_visitor_id,
      event_type: "checkout_completed",
      properties: { order_id: @order.id }
    )

    if track_result[:success]
      result = Mbuzz::Client.conversion(
        event_id: track_result[:event_id],
        conversion_type: "purchase",
        revenue: @order.total,
        properties: { items_count: @order.items.count }
      )

      @order.update!(
        mbuzz_conversion_id: result[:conversion_id],
        attribution_data: result[:attribution]
      ) if result[:success]
    end

    redirect_to order_confirmation_path(@order)
  end
end
```

### Background Job (Offline Conversion Import)

```ruby
class ImportOfflineConversionJob < ApplicationJob
  def perform(visitor_id, conversion_type, revenue)
    # Visitor-based - no event tracking needed
    result = Mbuzz::Client.conversion(
      visitor_id: visitor_id,
      conversion_type: conversion_type,
      revenue: revenue,
      properties: { source: "offline_import" }
    )

    Rails.logger.info "Imported conversion: #{result[:conversion_id]}" if result[:success]
  end
end
```

---

## Changelog

| Date | Change |
|------|--------|
| 2025-11-26 | Initial spec - support both `event_id` and `visitor_id` identifiers |

---

Built for mbuzz.co
