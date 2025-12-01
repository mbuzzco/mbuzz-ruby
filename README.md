# mbuzz

Server-side multi-touch attribution for Ruby. Track customer journeys, attribute conversions, know which channels drive revenue.

## Installation

Add to your Gemfile:

```ruby
gem 'mbuzz'
```

Then:

```bash
bundle install
```

## Quick Start

### 1. Initialize

```ruby
# config/initializers/mbuzz.rb
Mbuzz.init(api_key: ENV['MBUZZ_API_KEY'])
```

### 2. Track Events

Track steps in the customer journey:

```ruby
Mbuzz.event("page_view", url: request.url)
Mbuzz.event("add_to_cart", product_id: "SKU-123", price: 49.99)
Mbuzz.event("checkout_started", cart_total: 99.99)
```

### 3. Track Conversions

Record revenue-generating outcomes:

```ruby
Mbuzz.conversion("purchase",
  revenue: 99.99,
  order_id: order.id
)
```

### 4. Identify Users

Link visitors to known users (enables cross-device attribution):

```ruby
# On signup or login
Mbuzz.identify(current_user.id,
  traits: {
    email: current_user.email,
    name: current_user.name
  }
)
```

## Rails Integration

mbuzz auto-integrates with Rails via Railtie:
- Middleware for visitor and session cookie management
- Controller helpers for convenient access

### Controller Helpers

```ruby
class ApplicationController < ActionController::Base
  # Access current IDs
  mbuzz_visitor_id   # Returns the visitor ID from cookie
  mbuzz_user_id      # Returns user_id from session["user_id"]
  mbuzz_session_id   # Returns the session ID from cookie
end
```

**Note:** For tracking and identification, prefer the main API which auto-enriches events with URL/referrer:

```ruby
# Recommended - use main API in controllers
Mbuzz.event("page_view", page: request.path)
Mbuzz.identify(current_user.id, traits: { email: current_user.email })
```

### Context Accessors

Access IDs from anywhere in your request cycle:

```ruby
Mbuzz.visitor_id  # Current visitor ID (from cookie)
Mbuzz.user_id     # Current user ID (from session["user_id"])
Mbuzz.session_id  # Current session ID (from cookie)
```

## Rack / Sinatra Integration

For non-Rails apps, add the middleware manually:

```ruby
# config.ru or app.rb
require 'mbuzz'

Mbuzz.init(api_key: ENV['MBUZZ_API_KEY'])

use Mbuzz::Middleware::Tracking
run MyApp
```

## Configuration Options

```ruby
Mbuzz.init(
  api_key: "sk_live_...",             # Required - from mbuzz.co dashboard
  api_url: "https://mbuzz.co/api/v1", # Optional - API endpoint
  debug: false                        # Optional - enable debug logging
)
```

## The 4-Call Model

| Method | When to Use |
|--------|-------------|
| `init` | Once on app boot |
| `event` | User interactions, funnel steps |
| `conversion` | Purchases, signups, any revenue event |
| `identify` | Login, signup, when you know the user |

## Error Handling

mbuzz never raises exceptions. All methods return `false` on failure and log errors in debug mode.

## Requirements

- Ruby 3.0+
- Rails 6.0+ (for automatic integration) or any Rack app

## Links

- [Documentation](https://mbuzz.co/docs)
- [Dashboard](https://mbuzz.co/dashboard)

## License

MIT License
