# Conversions API - Technical Specification

**Version**: 1.0.0
**Created**: 2025-11-26
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
  visitor_id:,           # Required - The visitor who converted
  conversion_type:,      # Required - Type: "purchase", "signup", "upgrade", etc.
  revenue: nil,          # Optional - Revenue amount (numeric)
  currency: "USD",       # Optional - Currency code (default: USD)
  properties: {},        # Optional - Additional metadata
  event_id: nil          # Optional - Link to specific event that triggered conversion
)
```

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `visitor_id` | String | Yes | Visitor ID from cookie (`_mbuzz_vid`) |
| `conversion_type` | String | Yes | Type of conversion (e.g., "purchase", "signup") |
| `revenue` | Numeric | No | Revenue amount for ROI calculations |
| `currency` | String | No | ISO 4217 currency code (default: "USD") |
| `properties` | Hash | No | Additional conversion metadata |
| `event_id` | String | No | Link to triggering event (`evt_*` prefix ID) |

**Returns**:
- Success: `{ success: true, conversion_id: "conv_abc123", attribution: {...} }`
- Failure: `false`

**Example Usage**:
```ruby
# Basic conversion
result = Mbuzz::Client.conversion(
  visitor_id: cookies[:_mbuzz_vid],
  conversion_type: "purchase",
  revenue: 99.00
)

# Conversion with full details
result = Mbuzz::Client.conversion(
  visitor_id: mbuzz_visitor_id,
  conversion_type: "purchase",
  revenue: 299.00,
  currency: "USD",
  properties: {
    plan: "pro",
    billing_cycle: "annual",
    coupon_code: "SAVE20"
  }
)

# Conversion linked to triggering event (recommended)
track_result = Mbuzz::Client.track(
  visitor_id: mbuzz_visitor_id,
  event_type: "checkout_completed",
  properties: { order_id: order.id }
)

if track_result[:success]
  result = Mbuzz::Client.conversion(
    visitor_id: mbuzz_visitor_id,
    conversion_type: "purchase",
    revenue: order.total,
    event_id: track_result[:event_id]  # Links conversion to specific event
  )
end

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

## Backend Integration

### API Endpoint

**POST https://mbuzz.co/api/v1/conversions**

**Request Headers**:
```
Authorization: Bearer sk_live_abc123...
Content-Type: application/json
User-Agent: mbuzz-ruby/1.0.0
```

**Request Body**:
```json
{
  "visitor_id": "65dabef8d611f332d5bb88f5d6870c733d89f962594575b66f0e1de1ede1ebf0",
  "conversion_type": "purchase",
  "revenue": 99.00,
  "currency": "USD",
  "properties": {
    "plan": "pro",
    "billing_cycle": "annual"
  },
  "event_id": "evt_abc123"
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

def self.conversion(visitor_id:, conversion_type:, revenue: nil, currency: "USD", properties: {}, event_id: nil)
  return false unless valid_visitor_id?(visitor_id)
  return false unless valid_conversion_type?(conversion_type)
  return false unless valid_properties?(properties)

  payload = {
    visitor_id: visitor_id,
    conversion_type: conversion_type,
    currency: currency,
    properties: properties,
    timestamp: Time.now.utc.iso8601
  }.tap do |p|
    p[:revenue] = revenue if revenue
    p[:event_id] = event_id if event_id
  end

  response = Api.post_with_response(CONVERSIONS_PATH, payload)
  return false unless response

  {
    success: true,
    conversion_id: response["id"],
    attribution: response["attribution"]
  }
rescue StandardError => e
  log_error("Conversion error: #{e.message}")
  false
end

private_class_method def self.valid_conversion_type?(conversion_type)
  return false if conversion_type.nil?
  return false if conversion_type.to_s.strip.empty?
  true
end
```

### API Changes Required

The `Mbuzz::Api` class needs a new method that returns the response body (not just boolean):

```ruby
# lib/mbuzz/api.rb

def self.post_with_response(path, payload)
  return nil unless enabled_and_configured?

  response = http_client(path).request(build_request(path, payload))
  return nil unless success?(response)

  JSON.parse(response.body)
rescue StandardError => e
  log_error("#{e.class}: #{e.message}")
  nil
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
| `visitor_id` | Required, non-empty string | Return `false` |
| `conversion_type` | Required, non-empty string | Return `false` |
| `revenue` | Optional, numeric if present | Return `false` if non-numeric |
| `currency` | Optional, defaults to "USD" | N/A |
| `properties` | Optional, must be Hash | Return `false` if not Hash |

### Backend Validation

| Field | Rule | Error Response |
|-------|------|----------------|
| `visitor_id` | Must exist in account | 422 "Visitor not found" |
| `conversion_type` | Non-empty string | 422 "Conversion type required" |
| `revenue` | Numeric if present | 422 "Revenue must be numeric" |

---

## Error Handling

Following the gem's philosophy: **never raise exceptions**.

```ruby
# All errors return false
result = Mbuzz::Client.conversion(visitor_id: nil, conversion_type: "purchase")
# => false

result = Mbuzz::Client.conversion(visitor_id: "abc", conversion_type: "")
# => false

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
# test/mbuzz/client_test.rb

class ClientConversionTest < Minitest::Test
  def test_conversion_requires_visitor_id
    result = Mbuzz::Client.conversion(
      visitor_id: nil,
      conversion_type: "purchase"
    )
    assert_equal false, result
  end

  def test_conversion_requires_conversion_type
    result = Mbuzz::Client.conversion(
      visitor_id: "abc123",
      conversion_type: nil
    )
    assert_equal false, result
  end

  def test_conversion_rejects_empty_conversion_type
    result = Mbuzz::Client.conversion(
      visitor_id: "abc123",
      conversion_type: ""
    )
    assert_equal false, result
  end

  def test_conversion_accepts_valid_params
    stub_successful_conversion_response

    result = Mbuzz::Client.conversion(
      visitor_id: "abc123",
      conversion_type: "purchase",
      revenue: 99.00
    )

    assert result[:success]
    assert result[:conversion_id].start_with?("conv_")
    assert result[:attribution].is_a?(Hash)
  end

  def test_conversion_includes_attribution_models
    stub_successful_conversion_response

    result = Mbuzz::Client.conversion(
      visitor_id: "abc123",
      conversion_type: "purchase"
    )

    assert result[:attribution][:models].key?("first_touch")
    assert result[:attribution][:models].key?("last_touch")
    assert result[:attribution][:models].key?("linear")
  end
end
```

### Integration Tests (UAT)

```ruby
# Full attribution flow test
visitor_id = "uat_#{SecureRandom.hex(8)}"

# Create journey with 3 sessions
3.times do |i|
  Mbuzz::Client.track(
    visitor_id: visitor_id,
    event_type: "page_view",
    properties: {
      session_id: "sess_#{i}",
      utm_source: ["google", "facebook", "newsletter"][i],
      utm_medium: ["organic", "paid", "email"][i]
    }
  )
end

# Create conversion
result = Mbuzz::Client.conversion(
  visitor_id: visitor_id,
  conversion_type: "purchase",
  revenue: 99.00
)

# Verify attribution
assert result[:success]
assert_equal 3, result[:attribution][:sessions_analyzed]

# First touch should credit first session
first_touch = result[:attribution][:models]["first_touch"]
assert_equal "organic_search", first_touch.first[:channel]
assert_equal 1.0, first_touch.first[:credit]

# Last touch should credit last session
last_touch = result[:attribution][:models]["last_touch"]
assert_equal "email", last_touch.first[:channel]

# Linear should split evenly
linear = result[:attribution][:models]["linear"]
assert_equal 3, linear.size
linear.each do |credit|
  assert_in_delta 0.333, credit[:credit], 0.01
end
```

---

## Usage Examples

### Rails Controller

```ruby
class CheckoutsController < ApplicationController
  def create
    @order = Order.create!(order_params)

    # Track conversion with attribution
    result = Mbuzz::Client.conversion(
      visitor_id: mbuzz_visitor_id,
      conversion_type: "purchase",
      revenue: @order.total,
      properties: {
        order_id: @order.id,
        items_count: @order.items.count,
        coupon_code: @order.coupon_code
      }
    )

    if result[:success]
      # Store attribution for analytics
      @order.update!(
        mbuzz_conversion_id: result[:conversion_id],
        attribution_data: result[:attribution]
      )
    end

    redirect_to order_confirmation_path(@order)
  end
end
```

### Background Job

```ruby
class ProcessSubscriptionJob < ApplicationJob
  def perform(subscription_id)
    subscription = Subscription.find(subscription_id)
    visitor = subscription.user.mbuzz_visitor_id

    result = Mbuzz::Client.conversion(
      visitor_id: visitor,
      conversion_type: "subscription",
      revenue: subscription.amount,
      properties: {
        plan: subscription.plan.name,
        billing_cycle: subscription.billing_cycle,
        trial: subscription.trial?
      }
    )

    subscription.update!(attribution_data: result[:attribution]) if result[:success]
  end
end
```

---

## Migration Path

### From REST API to SDK

**Before** (REST API):
```ruby
uri = URI("https://mbuzz.co/api/v1/conversions")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Post.new(uri.path)
request["Authorization"] = "Bearer #{api_key}"
request["Content-Type"] = "application/json"
request.body = {
  visitor_id: visitor_id,
  conversion_type: "purchase",
  revenue: 99.00
}.to_json

response = http.request(request)
data = JSON.parse(response.body)
```

**After** (SDK):
```ruby
result = Mbuzz::Client.conversion(
  visitor_id: visitor_id,
  conversion_type: "purchase",
  revenue: 99.00
)
```

---

## Success Criteria

- [ ] `Mbuzz::Client.conversion` method implemented
- [ ] Returns `false` on validation failure
- [ ] Returns attribution hash on success
- [ ] Handles network errors gracefully
- [ ] Unit tests cover all validation cases
- [ ] Integration test validates full attribution flow
- [ ] Documentation updated in README

---

## Dependencies

**None** - Uses existing `Mbuzz::Api` infrastructure with new `post_with_response` method.

---

Built for mbuzz.co
