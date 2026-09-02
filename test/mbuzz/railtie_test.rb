# frozen_string_literal: true

require "test_helper"

class Mbuzz::RailtieTest < Minitest::Test
  def test_railtie_file_exists
    assert File.exist?(railtie_source)
  end

  # A Rails app never mounts middleware by hand, so a fix that isn't mounted
  # here is a fix nobody receives.
  def test_mounts_the_session_endpoint_ahead_of_tracking
    source = File.read(railtie_source)

    endpoint_at = source.index("Mbuzz::Middleware::SessionEndpoint")
    tracking_at = source.index("Mbuzz::Middleware::Tracking")

    refute_nil endpoint_at, "the session endpoint must be mounted for cached pages to work"
    assert endpoint_at < tracking_at, "the endpoint answers its own path; it belongs ahead of Tracking"
  end

  private

  def railtie_source
    File.expand_path("../../lib/mbuzz/railtie.rb", __dir__)
  end
end
