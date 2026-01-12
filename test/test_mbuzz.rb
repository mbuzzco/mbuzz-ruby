# frozen_string_literal: true

require "test_helper"

class TestMbuzz < Minitest::Test
  def setup
    # Clear request context
    Mbuzz::RequestContext.instance_variable_set(:@current, nil)
  end

  def test_that_it_has_a_version_number
    refute_nil ::Mbuzz::VERSION
  end

  # Visitor ID behavior tests (v1.3.0+)
  # visitor_id returns nil when no request context - no more fallback generation

  def test_visitor_id_returns_nil_when_no_request_context
    # No request context exists (like in background job)
    visitor_id = Mbuzz.visitor_id

    assert_nil visitor_id, "visitor_id should return nil without request context"
  end
end
