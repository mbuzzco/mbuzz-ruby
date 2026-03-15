# frozen_string_literal: true

require "test_helper"

# Tests for explicit visitor_id requirement
# After SDK changes, events/conversions should FAIL when:
# - Called outside request context (no middleware)
# - No explicit visitor_id provided
#
# This prevents orphan visitors from background jobs
class ExplicitVisitorIdTest < Minitest::Test
  def setup
    @original_config = Mbuzz.instance_variable_get(:@config)
    Mbuzz.instance_variable_set(:@config, nil)

    Mbuzz.init(api_key: "sk_test_123")
    Mbuzz.config.api_url = "http://localhost:3000/api/v1"

    # Clear any cached fallback visitor_id
    Mbuzz.instance_variable_set(:@fallback_visitor_id, nil)
    # Clear request context (simulates background job)
    Mbuzz::RequestContext.instance_variable_set(:@current, nil)
  end

  def teardown
    Mbuzz.instance_variable_set(:@config, @original_config)
  end

  # -------------------------------------------------------------------
  # Mbuzz.event tests
  # -------------------------------------------------------------------

  def test_event_without_context_and_without_explicit_visitor_id_fails
    # Simulates: background job calling Mbuzz.event() without visitor_id
    # No request context exists, no explicit visitor_id passed
    stub_api_success do
      result = Mbuzz.event("background_event", order_id: "123")

      assert_equal false, result,
        "Event without context and without explicit visitor_id should return false"
    end
  end

  def test_event_with_explicit_visitor_id_succeeds
    # Simulates: background job calling Mbuzz.event() WITH visitor_id
    # This is the correct pattern for background jobs
    stub_api_success_with_event do
      result = Mbuzz.event("background_event", visitor_id: "abc123def456", order_id: "123")

      refute_equal false, result,
        "Event with explicit visitor_id should succeed"
    end
  end

  def test_event_with_context_works_normally
    # Simulates: normal request with middleware (has RequestContext)
    stub_api_success_with_event do
      with_request_context(visitor_id: "vis_from_context") do
        result = Mbuzz.event("normal_event", page: "/products")

        refute_equal false, result,
          "Event within request context should succeed"
      end
    end
  end

  # -------------------------------------------------------------------
  # Mbuzz.conversion tests
  # -------------------------------------------------------------------

  def test_conversion_without_context_and_without_explicit_visitor_id_fails
    stub_api_success do
      result = Mbuzz.conversion("purchase", revenue: 99.99)

      assert_equal false, result,
        "Conversion without context and without explicit visitor_id should return false"
    end
  end

  def test_conversion_with_explicit_visitor_id_succeeds
    stub_conversion_success do
      result = Mbuzz.conversion("purchase", visitor_id: "abc123def456", revenue: 99.99)

      refute_equal false, result,
        "Conversion with explicit visitor_id should succeed"
    end
  end

  def test_conversion_with_user_id_only_succeeds
    # user_id is also a valid identifier
    stub_conversion_success do
      result = Mbuzz.conversion("payment", user_id: "user_123", revenue: 49.99)

      refute_equal false, result,
        "Conversion with user_id should succeed even without visitor_id"
    end
  end

  def test_conversion_with_context_works_normally
    stub_conversion_success do
      with_request_context(visitor_id: "vis_from_context") do
        result = Mbuzz.conversion("purchase", revenue: 99.99)

        refute_equal false, result,
          "Conversion within request context should succeed"
      end
    end
  end

  # -------------------------------------------------------------------
  # Mbuzz.visitor_id behavior tests
  # -------------------------------------------------------------------

  def test_visitor_id_returns_nil_without_context
    # After changes, visitor_id should return nil when no context
    # (not generate a fallback)
    visitor_id = Mbuzz.visitor_id

    assert_nil visitor_id,
      "visitor_id should return nil when no request context"
  end

  private

  def stub_api_success
    Mbuzz::Api.stub(:post, true) do
      yield
    end
  end

  def stub_api_success_with_event
    response = {
      "accepted" => 1,
      "rejected" => [],
      "events" => [
        {
          "id" => "evt_abc123def456",
          "event_type" => "background_event",
          "visitor_id" => "abc123def456",
          "session_id" => "sess_xyz789",
          "status" => "accepted"
        }
      ]
    }
    Mbuzz::Api.stub(:post_with_response, response) do
      yield
    end
  end

  def stub_conversion_success
    response = {
      "conversion" => {
        "id" => "conv_xyz789",
        "visitor_id" => "vis_abc123",
        "conversion_type" => "purchase",
        "revenue" => "99.0"
      },
      "attribution" => { "status" => "pending" }
    }
    Mbuzz::Api.stub(:post_with_response, response) do
      yield
    end
  end

  def with_request_context(visitor_id:)
    mock_request = MockRequest.new(visitor_id)
    Mbuzz::RequestContext.with_context(request: mock_request) do
      yield
    end
  end

  # Minimal mock request for testing
  class MockRequest
    def initialize(visitor_id)
      @visitor_id = visitor_id
    end

    def env
      {
        Mbuzz::ENV_VISITOR_ID_KEY => @visitor_id,
        "HTTP_X_FORWARDED_FOR" => "192.168.1.1",
        "HTTP_USER_AGENT" => "Test Agent"
      }
    end

    def url
      "http://localhost/test"
    end

    def referrer
      nil
    end

    def ip
      "192.168.1.1"
    end

    def user_agent
      "Test Agent"
    end
  end
end
