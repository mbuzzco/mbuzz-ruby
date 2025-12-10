# frozen_string_literal: true

require "test_helper"

class TestMbuzz < Minitest::Test
  def setup
    # Clear any cached fallback visitor_id between tests
    Mbuzz.instance_variable_set(:@fallback_visitor_id, nil)
    # Clear request context
    Mbuzz::RequestContext.instance_variable_set(:@current, nil)
  end

  def test_that_it_has_a_version_number
    refute_nil ::Mbuzz::VERSION
  end

  # Visitor ID fallback tests

  def test_visitor_id_returns_fallback_when_no_request_context
    # No request context exists (like in Rails console)
    visitor_id = Mbuzz.visitor_id

    refute_nil visitor_id
    assert_equal 64, visitor_id.length # SecureRandom.hex(32) = 64 chars
  end

  def test_visitor_id_fallback_is_consistent_within_process
    # Same visitor_id should be returned for multiple calls
    first_call = Mbuzz.visitor_id
    second_call = Mbuzz.visitor_id

    assert_equal first_call, second_call
  end

  def test_visitor_id_fallback_is_valid_hex_string
    visitor_id = Mbuzz.visitor_id

    assert_match(/\A[a-f0-9]{64}\z/, visitor_id)
  end
end
