# frozen_string_literal: true

require "test_helper"

class Mbuzz::ClientTest < Minitest::Test
  def setup
    @original_config = Mbuzz.instance_variable_get(:@config)
    Mbuzz.instance_variable_set(:@config, nil)

    Mbuzz.configure do |config|
      config.api_key = "sk_test_123"
      config.api_url = "https://mbuzz.co/api/v1"
    end
  end

  def teardown
    Mbuzz.instance_variable_set(:@config, @original_config)
  end

  # Track tests - v1.1 returns hash with event_id on success
  def test_track_returns_event_id_on_success
    stub_api_success_with_event do
      result = track_result
      assert result[:success]
      assert_equal "evt_abc123def456", result[:event_id]
      assert_equal "page_view", result[:event_type]
      assert_equal "visitor_hash", result[:visitor_id]
      assert_equal "sess_xyz789", result[:session_id]
    end
  end

  def test_track_returns_false_on_failure
    stub_api_failure do
      assert_equal false, track_result
    end
  end

  def test_track_returns_false_when_api_returns_no_events
    stub_api_success_with_response({ "accepted" => 0, "events" => [] }) do
      assert_equal false, track_result
    end
  end

  def test_track_returns_false_when_api_returns_nil_events
    stub_api_success_with_response({ "accepted" => 0 }) do
      assert_equal false, track_result
    end
  end

  def test_track_works_with_user_id
    @user_id = 123
    @visitor_id = nil
    stub_api_success_with_event do
      result = track_result
      assert result[:success]
    end
  end

  def test_track_works_with_visitor_id
    @user_id = nil
    @visitor_id = "visitor123"
    stub_api_success_with_event do
      result = track_result
      assert result[:success]
    end
  end

  def test_track_still_truthy_for_boolean_checks
    stub_api_success_with_event do
      result = track_result
      # Backwards compatibility: result is truthy (hash)
      assert result
      if result
        assert true, "Boolean check still works"
      end
    end
  end

  # Identify tests
  def test_identify_returns_true_on_success
    stub_api_success do
      assert_equal true, identify_result
    end
  end

  def test_identify_returns_false_on_failure
    stub_api_failure do
      assert_equal false, identify_result
    end
  end

  # Validation tests - ensuring invalid input doesn't crash the app
  def test_track_returns_false_with_nil_event_type
    @event_type = nil
    assert_equal false, track_result
  end

  def test_track_returns_false_with_empty_event_type
    @event_type = ""
    assert_equal false, track_result
  end

  def test_track_returns_false_with_whitespace_event_type
    @event_type = "   "
    assert_equal false, track_result
  end

  def test_track_returns_false_with_invalid_properties
    @properties = "not a hash"
    assert_equal false, track_result
  end

  def test_track_returns_false_without_user_or_visitor_id
    @user_id = nil
    @visitor_id = nil
    assert_equal false, track_result
  end

  def test_identify_returns_false_with_nil_user_id
    @user_id = nil
    assert_equal false, identify_result
  end

  def test_identify_returns_false_with_invalid_traits
    @traits = "not a hash"
    assert_equal false, identify_result
  end

  # Conversion tests - dual-path: event_id OR visitor_id

  def test_conversion_returns_success_with_event_id
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        event_id: "evt_abc123",
        conversion_type: "purchase"
      )
      assert result[:success]
      assert_equal "conv_xyz789", result[:conversion_id]
      assert result[:attribution].is_a?(Hash)
    end
  end

  def test_conversion_returns_success_with_visitor_id
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        visitor_id: "abc123",
        conversion_type: "purchase"
      )
      assert result[:success]
      assert_equal "conv_xyz789", result[:conversion_id]
    end
  end

  def test_conversion_returns_success_with_both_identifiers
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        event_id: "evt_abc123",
        visitor_id: "abc123",
        conversion_type: "purchase"
      )
      assert result[:success]
    end
  end

  def test_conversion_returns_false_when_no_identifier
    result = Mbuzz::Client.conversion(
      conversion_type: "purchase"
    )
    assert_equal false, result
  end

  def test_conversion_returns_false_on_api_failure
    stub_api_failure do
      result = Mbuzz::Client.conversion(
        event_id: "evt_abc123",
        conversion_type: "purchase"
      )
      assert_equal false, result
    end
  end

  def test_conversion_requires_conversion_type
    result = Mbuzz::Client.conversion(
      event_id: "evt_abc123",
      conversion_type: nil
    )
    assert_equal false, result
  end

  def test_conversion_rejects_empty_conversion_type
    result = Mbuzz::Client.conversion(
      event_id: "evt_abc123",
      conversion_type: ""
    )
    assert_equal false, result
  end

  def test_conversion_rejects_whitespace_conversion_type
    result = Mbuzz::Client.conversion(
      event_id: "evt_abc123",
      conversion_type: "   "
    )
    assert_equal false, result
  end

  def test_conversion_accepts_revenue
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        event_id: "evt_abc123",
        conversion_type: "purchase",
        revenue: 99.00
      )
      assert result[:success]
    end
  end

  def test_conversion_accepts_currency
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        event_id: "evt_abc123",
        conversion_type: "purchase",
        revenue: 99.00,
        currency: "EUR"
      )
      assert result[:success]
    end
  end

  def test_conversion_accepts_properties
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        event_id: "evt_abc123",
        conversion_type: "purchase",
        properties: { plan: "pro" }
      )
      assert result[:success]
    end
  end

  def test_conversion_rejects_invalid_properties
    result = Mbuzz::Client.conversion(
      event_id: "evt_abc123",
      conversion_type: "purchase",
      properties: "not a hash"
    )
    assert_equal false, result
  end

  def test_conversion_includes_attribution_status
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        event_id: "evt_abc123",
        conversion_type: "purchase"
      )
      assert_equal "pending", result[:attribution]["status"]
    end
  end

  # Acquisition attribution tests

  def test_conversion_accepts_user_id
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        user_id: "user_123",
        conversion_type: "signup"
      )
      assert result[:success]
    end
  end

  def test_conversion_accepts_is_acquisition
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        user_id: "user_123",
        conversion_type: "signup",
        is_acquisition: true
      )
      assert result[:success]
    end
  end

  def test_conversion_accepts_inherit_acquisition
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        user_id: "user_123",
        conversion_type: "payment",
        revenue: 49.00,
        inherit_acquisition: true
      )
      assert result[:success]
    end
  end

  def test_conversion_user_id_satisfies_identifier_requirement
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        user_id: "user_123",
        conversion_type: "signup"
      )
      assert result[:success]
    end
  end

  def test_conversion_still_truthy_for_boolean_checks
    stub_conversion_success do
      result = Mbuzz::Client.conversion(
        event_id: "evt_abc123",
        conversion_type: "purchase"
      )
      # Backwards compatibility: result is truthy (hash)
      assert result
      if result
        assert true, "Boolean check still works"
      end
    end
  end

  # Session tests

  def test_session_returns_true_on_success
    stub_api_success do
      result = Mbuzz::Client.session(
        visitor_id: "visitor123",
        session_id: "session456",
        url: "https://example.com/landing?utm_source=google"
      )
      assert_equal true, result
    end
  end

  def test_session_returns_false_on_failure
    stub_api_failure do
      result = Mbuzz::Client.session(
        visitor_id: "visitor123",
        session_id: "session456",
        url: "https://example.com/landing"
      )
      assert_equal false, result
    end
  end

  def test_session_requires_visitor_id
    result = Mbuzz::Client.session(
      visitor_id: nil,
      session_id: "session456",
      url: "https://example.com/landing"
    )
    assert_equal false, result
  end

  def test_session_requires_session_id
    result = Mbuzz::Client.session(
      visitor_id: "visitor123",
      session_id: nil,
      url: "https://example.com/landing"
    )
    assert_equal false, result
  end

  def test_session_requires_url
    result = Mbuzz::Client.session(
      visitor_id: "visitor123",
      session_id: "session456",
      url: nil
    )
    assert_equal false, result
  end

  def test_session_accepts_referrer
    stub_api_success do
      result = Mbuzz::Client.session(
        visitor_id: "visitor123",
        session_id: "session456",
        url: "https://example.com/landing",
        referrer: "https://google.com/search"
      )
      assert_equal true, result
    end
  end

  def test_session_accepts_started_at
    stub_api_success do
      result = Mbuzz::Client.session(
        visitor_id: "visitor123",
        session_id: "session456",
        url: "https://example.com/landing",
        started_at: "2025-11-28T10:30:00Z"
      )
      assert_equal true, result
    end
  end

  private

  def track_result
    Mbuzz::Client.track(
      user_id: defined?(@user_id) ? @user_id : 123,
      visitor_id: @visitor_id,
      event_type: defined?(@event_type) ? @event_type : "Signup",
      properties: @properties || {}
    )
  end

  def identify_result
    Mbuzz::Client.identify(
      user_id: defined?(@user_id) ? @user_id : 123,
      traits: @traits || {}
    )
  end

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
          "event_type" => "page_view",
          "visitor_id" => "visitor_hash",
          "session_id" => "sess_xyz789",
          "status" => "accepted"
        }
      ]
    }
    Mbuzz::Api.stub(:post_with_response, response) do
      yield
    end
  end

  def stub_api_success_with_response(response)
    Mbuzz::Api.stub(:post_with_response, response) do
      yield
    end
  end

  def stub_api_failure
    Mbuzz::Api.stub(:post_with_response, nil) do
      yield
    end
  end

  def stub_conversion_success
    response = {
      "conversion" => {
        "id" => "conv_xyz789",
        "visitor_id" => "vis_abc123",
        "conversion_type" => "purchase",
        "revenue" => "99.0",
        "converted_at" => "2025-11-26T10:30:00Z"
      },
      "attribution" => {
        "status" => "pending"
      }
    }
    Mbuzz::Api.stub(:post_with_response, response) do
      yield
    end
  end
end
