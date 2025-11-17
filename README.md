# mbuzz - Ruby Client

Server-side multi-touch attribution tracking for Ruby applications. Track user journeys, conversions, and marketing attribution with zero client-side JavaScript.

[![Gem Version](https://badge.fury.io/rb/mbuzz.svg)](https://badge.fury.io/rb/mbuzz)
[![Build Status](https://github.com/mbuzz/mbuzz-ruby/workflows/CI/badge.svg)](https://github.com/mbuzz/mbuzz-ruby/actions)

## Overview

mbuzz is a server-side attribution tracking system that captures:

- **UTM parameters** from landing pages (first-touch attribution)
- **Page views** with full URL and referrer data
- **Conversion events** (signups, purchases, trials, etc.)
- **Anonymous visitor tracking** via secure cookies
- **Multi-session attribution** for complete customer journey analysis

Unlike client-side analytics (Google Analytics, Segment), mbuzz tracks everything server-side, making it:

- **Ad-blocker proof** - No JavaScript to block
- **Privacy-friendly** - No third-party cookies
- **Accurate** - No client-side sampling or data loss
- **Framework-agnostic** - Works with Rails, Sinatra, Hanami, or any Rack app

## Installation

Add to your Gemfile:

```ruby
gem 'mbuzz'
```

Then run:

```bash
bundle install
```

## Quick Start

### 1. Get Your API Key

Sign up at [mbuzz.co](https://mbuzz.co) and copy your API key from the dashboard.

### 2. Configure the Gem

Create an initializer (Rails):

```ruby
# config/initializers/mbuzz.rb
Mbuzz.configure do |config|
  config.api_key = ENV['MBUZZ_API_KEY']
  config.api_url = ENV.fetch('MBUZZ_API_URL', 'https://mbuzz.co/api/v1')
  config.enabled = !Rails.env.test?
end
```

### 3. Track Events

**Automatic Page View Tracking** (Rails middleware):

```ruby
# Automatically tracks all page views with UTM parameters
# No code required - just install and configure!
```

**Manual Event Tracking**:

```ruby
class SignupsController < ApplicationController
  def create
    @user = User.create!(signup_params)

    # Identify the user
    Mbuzz.identify(
      user_id: @user.id,
      traits: {
        email: @user.email,
        name: @user.name,
        plan: @user.plan
      }
    )

    # Track the conversion
    Mbuzz.track(
      user_id: @user.id,
      event: 'Signup',
      properties: {
        plan: @user.plan,
        trial_days: 14
      }
    )

    redirect_to dashboard_path
  end
end
```

## Core Concepts

### Visitor Identification

mbuzz automatically generates a unique visitor ID for each anonymous user and stores it in a secure cookie (`_mbuzz_vid`). This enables:

- **Cross-session tracking** - Same visitor across multiple visits
- **Attribution linking** - Connect anonymous behavior to known users after signup
- **Privacy compliance** - No third-party cookies or fingerprinting

### Session Tracking

Sessions capture UTM parameters and referrer data on first page view, then maintain that attribution for all events in the session:

- **Session duration**: 30 minutes of inactivity
- **First-touch attribution**: UTM parameters captured once per session
- **Multi-touch support**: Each new session can have different attribution

### Event Types

- **page_view** - Automatic via middleware
- **signup** - User registration
- **purchase** - Completed transaction
- **trial_started** - Free trial activation
- **subscription_created** - Paid subscription
- **custom** - Any event you define

## API Reference

### Configuration

```ruby
Mbuzz.configure do |config|
  config.api_key = 'sk_live_...'           # Required
  config.api_url = 'https://mbuzz.co/api/v1'  # Optional
  config.enabled = true                    # Optional (default: true)
  config.batch_size = 50                   # Optional (default: 50)
  config.flush_interval = 30               # Optional (seconds, default: 30)
  config.debug = false                     # Optional (default: false)
end
```

### Mbuzz.track

Track custom events.

```ruby
Mbuzz.track(
  user_id: String|Integer,        # Required (or anonymous_id)
  anonymous_id: String,           # Required (or user_id)
  event: String,                  # Required
  properties: Hash,               # Optional
  timestamp: Time                 # Optional (defaults to Time.current)
)
```

**Parameters:**

- `user_id` - Your database user ID (use after user signs up)
- `anonymous_id` - Visitor ID from cookies (use before signup)
- `event` - Event name (e.g., "Signup", "Purchase", "Trial Started")
- `properties` - Event metadata (plan, amount, funnel, etc.)
- `timestamp` - When the event occurred (defaults to current time)

**Returns:** `true` on success, `false` on failure (never raises exceptions)

**Example:**

```ruby
Mbuzz.track(
  user_id: current_user.id,
  event: 'Purchase',
  properties: {
    amount: 99.99,
    currency: 'USD',
    items: ['Widget', 'Gadget']
  }
)
```

### Mbuzz.identify

Identify a user and update their traits.

```ruby
Mbuzz.identify(
  user_id: String|Integer,        # Required
  traits: Hash,                   # Optional
  timestamp: Time                 # Optional
)
```

**Parameters:**

- `user_id` - Your database user ID
- `traits` - User attributes (email, name, plan, etc.)
- `timestamp` - When identification occurred

**When to call:**

- On signup (associate user_id with anonymous visitor)
- When user traits change (upgrade plan, change email)
- On login (optional - refresh traits)

**Example:**

```ruby
Mbuzz.identify(
  user_id: @user.id,
  traits: {
    email: @user.email,
    name: @user.name,
    plan: @user.plan,
    created_at: @user.created_at
  }
)
```

### Mbuzz.alias

Link anonymous visitor to user_id on signup.

```ruby
Mbuzz.alias(
  user_id: String|Integer,        # Required (new ID)
  previous_id: String             # Required (old anonymous_id)
)
```

**Use case:** Connect pre-signup behavior to user account.

**Example:**

```ruby
# Before signup: track anonymous visitor
Mbuzz.track(
  anonymous_id: mbuzz_visitor_id,
  event: 'Landing Page View'
)

# On signup: link anonymous visitor to user
Mbuzz.alias(
  user_id: @user.id,
  previous_id: mbuzz_visitor_id
)
```

### Helper: mbuzz_visitor_id

Available in Rails controllers. Returns the visitor ID from cookies (or creates one).

```ruby
class LandingController < ApplicationController
  def show
    visitor_id = mbuzz_visitor_id  # Automatically generates and stores in cookie

    Mbuzz.track(
      anonymous_id: visitor_id,
      event: 'Landing Page View'
    )
  end
end
```

## Usage Patterns

### Anonymous Visitor Tracking

Track users before they sign up:

```ruby
class LandingController < ApplicationController
  def show
    Mbuzz.track(
      anonymous_id: mbuzz_visitor_id,
      event: 'Landing Page View',
      properties: {
        page: params[:page],
        variant: 'A'
      }
    )
  end
end
```

### User Signup Flow

Complete attribution from anonymous visitor to known user:

```ruby
class SignupsController < ApplicationController
  def create
    @user = User.create!(signup_params)

    # Link anonymous visitor to user account
    Mbuzz.alias(
      user_id: @user.id,
      previous_id: mbuzz_visitor_id
    )

    # Identify the user
    Mbuzz.identify(
      user_id: @user.id,
      traits: {
        email: @user.email,
        name: @user.name
      }
    )

    # Track the conversion
    Mbuzz.track(
      user_id: @user.id,
      event: 'Signup'
    )

    redirect_to dashboard_path
  end
end
```

### Funnel Tracking

Track multi-step conversion funnels:

```ruby
class SubscriptionsController < ApplicationController
  def pricing
    Mbuzz.track(
      user_id: current_user.id,
      event: 'Pricing Page Viewed',
      properties: { funnel: 'subscription' }
    )
  end

  def checkout
    Mbuzz.track(
      user_id: current_user.id,
      event: 'Checkout Started',
      properties: { funnel: 'subscription' }
    )
  end

  def create
    @subscription = Subscription.create!(params)

    Mbuzz.track(
      user_id: current_user.id,
      event: 'Subscription Created',
      properties: {
        funnel: 'subscription',
        plan: @subscription.plan,
        amount: @subscription.amount_cents
      }
    )

    redirect_to dashboard_path
  end
end
```

### Background Jobs & Models

Track events from anywhere (jobs, models, rake tasks):

```ruby
class Subscription < ApplicationRecord
  after_create :track_conversion

  private

  def track_conversion
    Mbuzz.track(
      user_id: user_id,
      event: 'Subscription Created',
      properties: {
        plan: plan,
        amount: amount_cents
      }
    )
  end
end

class InvoiceGenerationJob < ApplicationJob
  def perform(user_id)
    # ... generate invoice

    Mbuzz.track(
      user_id: user_id,
      event: 'Invoice Generated'
    )
  end
end
```

**How it works:** The backend looks up the visitor/session by user_id to maintain attribution even without request context.

## How It Works

### With Request Context (Controllers)

```ruby
class SignupsController < ApplicationController
  def create
    Mbuzz.track(user_id: @user.id, event: 'Signup')
  end
end
```

**Behind the scenes:**

1. Gem reads `request.original_url` (captures UTM params)
2. Gem reads `request.referrer`
3. Gem reads cookies for visitor/session tracking
4. Sends all data to mbuzz API
5. API returns Set-Cookie headers
6. Gem forwards cookies to response

### Without Request Context (Background Jobs)

```ruby
class SubscriptionJob < ApplicationJob
  def perform(user_id)
    Mbuzz.track(user_id: user_id, event: 'Trial Expired')
  end
end
```

**Behind the scenes:**

1. No URL/referrer available (not needed for this event)
2. Backend looks up visitor/session by user_id
3. Attribution maintained via user_id linkage

## Architecture

### Thread-Safe Request Context

The gem uses thread-local storage to safely capture request/response objects in multi-threaded environments:

```ruby
# Middleware captures request context
Mbuzz::RequestContext.with_context(request: request, response: response) do
  # Your controller action runs here
  # All mbuzz calls have access to request/response
end
```

### Automatic Cookie Forwarding

When the API returns Set-Cookie headers (for visitor/session IDs), the gem automatically forwards them to your application's response.

### Error Handling

All tracking calls fail silently and never raise exceptions:

```ruby
result = Mbuzz.track(...)
# Returns true on success, false on failure
# Errors logged to Rails.logger but never raised
```

This ensures tracking failures never break your application.

## Comparison to Other Tools

| Feature | Segment | Google Analytics | mbuzz |
|---------|---------|------------------|-------|
| **API Style** | `Analytics.track(...)` | JavaScript only | `Mbuzz.track(...)` |
| **Server-Side** | Yes | No (GA4 has API) | Yes |
| **Ad-Blocker Proof** | Yes | No | Yes |
| **Framework Support** | Many | Browser only | Rails (more coming) |
| **Dependencies** | Many | None | Zero |
| **Focus** | Multi-destination | Analytics | Attribution |
| **UTM Tracking** | Manual | Automatic | Automatic |
| **Anonymous Tracking** | Yes | Yes | Yes |

**mbuzz advantages:**

- Zero dependencies (pure Ruby, uses only net/http)
- Server-side only (no JavaScript required)
- Purpose-built for marketing attribution
- Simpler API (no batching/queuing complexity in client)
- Framework-agnostic design

## Testing

### Disabling in Tests

```ruby
# config/environments/test.rb
Mbuzz.configure do |config|
  config.enabled = false
end
```

### Stubbing Calls

```ruby
# In your tests
allow(Mbuzz).to receive(:track).and_return(true)
allow(Mbuzz).to receive(:identify).and_return(true)
```

### Integration Tests

The gem includes a test mode that captures calls without sending to API:

```ruby
Mbuzz.test_mode = true

# Make tracking calls
Mbuzz.track(user_id: 1, event: 'Test')

# Assert on captured calls
expect(Mbuzz.test_calls.last).to include(event: 'Test')

# Clear test calls
Mbuzz.clear_test_calls
```

## Development

After checking out the repo:

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rake test

# Run linter
bundle exec standardrb

# Interactive console
bin/console
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/mbuzz/mbuzz-ruby.

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests
4. Make your changes
5. Run tests (`bundle exec rake test`)
6. Commit your changes (`git commit -am 'Add my feature'`)
7. Push to the branch (`git push origin feature/my-feature`)
8. Create a Pull Request

## Security

If you discover a security vulnerability, please email security@mbuzz.co instead of using the issue tracker.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Support

- **Documentation**: https://mbuzz.co/docs
- **API Reference**: https://mbuzz.co/api/docs
- **Issues**: https://github.com/mbuzz/mbuzz-ruby/issues
- **Email**: support@mbuzz.co

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Roadmap

- [x] **v1.0** - Core tracking (page views, events, identification)
- [x] **v1.0** - Rails integration (middleware, helpers)
- [x] **v1.0** - Anonymous visitor tracking
- [x] **v1.0** - UTM parameter capture
- [ ] **v1.1** - Sinatra/Rack support
- [ ] **v1.2** - Hanami support

---

Built with love by the mbuzz team.
