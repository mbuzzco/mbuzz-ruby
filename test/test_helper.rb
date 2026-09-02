# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "mbuzz"

# Disable minitest plugins to avoid loading Rails
ENV["MT_NO_PLUGINS"] = "1"

require "minitest/autorun"

# Mbuzz::Current is an ActiveSupport::CurrentAttributes. In a Rails app the
# executor resets it between requests; a test suite has no executor, so a
# user_id written by identify() in one test is still set in the next one and
# silently satisfies assertions that expect no identity. Reset it per test.
class Minitest::Test
  def before_setup
    super
    Mbuzz::Current.reset if defined?(Mbuzz::Current)
  end
end
