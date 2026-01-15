# frozen_string_literal: true

require "test_helper"

class Mbuzz::Client::SessionRequestTest < Minitest::Test
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

  # Basic functionality tests

  def test_call_returns_success_on_accepted_response
    stub_session_success do
      result = build_request.call
      assert result[:success]
      assert_equal "vis_abc123", result[:visitor_id]
      assert_equal "sess_xyz789", result[:session_id]
      assert_equal "paid_search", result[:channel]
    end
  end

  def test_call_returns_false_on_failure
    stub_session_failure do
      assert_equal false, build_request.call
    end
  end

  # Validation tests

  def test_requires_visitor_id
    request = Mbuzz::Client::SessionRequest.new(
      visitor_id: nil,
      session_id: "sess123",
      url: "https://example.com/"
    )
    assert_equal false, request.call
  end

  def test_requires_session_id
    request = Mbuzz::Client::SessionRequest.new(
      visitor_id: "vis123",
      session_id: nil,
      url: "https://example.com/"
    )
    assert_equal false, request.call
  end

  def test_requires_url
    request = Mbuzz::Client::SessionRequest.new(
      visitor_id: "vis123",
      session_id: "sess123",
      url: nil
    )
    assert_equal false, request.call
  end

  def test_rejects_empty_visitor_id
    request = Mbuzz::Client::SessionRequest.new(
      visitor_id: "",
      session_id: "sess123",
      url: "https://example.com/"
    )
    assert_equal false, request.call
  end

  def test_rejects_whitespace_visitor_id
    request = Mbuzz::Client::SessionRequest.new(
      visitor_id: "   ",
      session_id: "sess123",
      url: "https://example.com/"
    )
    assert_equal false, request.call
  end

  # Optional parameters

  def test_accepts_referrer
    stub_session_success do
      request = Mbuzz::Client::SessionRequest.new(
        visitor_id: "vis123",
        session_id: "sess123",
        url: "https://example.com/",
        referrer: "https://google.com/search"
      )
      assert request.call[:success]
    end
  end

  def test_accepts_device_fingerprint
    stub_session_success do
      request = Mbuzz::Client::SessionRequest.new(
        visitor_id: "vis123",
        session_id: "sess123",
        url: "https://example.com/",
        device_fingerprint: "abc123fingerprint456"
      )
      assert request.call[:success]
    end
  end

  def test_accepts_started_at
    stub_session_success do
      request = Mbuzz::Client::SessionRequest.new(
        visitor_id: "vis123",
        session_id: "sess123",
        url: "https://example.com/",
        started_at: Time.now.utc.iso8601
      )
      assert request.call[:success]
    end
  end

  # Error handling

  def test_handles_network_errors_gracefully
    Mbuzz::Api.stub(:post_with_response, ->(*) { raise StandardError, "Network error" }) do
      result = build_request.call
      assert_equal false, result
    end
  end

  def test_handles_nil_response
    Mbuzz::Api.stub(:post_with_response, nil) do
      result = build_request.call
      assert_equal false, result
    end
  end

  def test_handles_unexpected_response_format
    Mbuzz::Api.stub(:post_with_response, { "unexpected" => "format" }) do
      result = build_request.call
      assert_equal false, result
    end
  end

  private

  def build_request
    Mbuzz::Client::SessionRequest.new(
      visitor_id: "vis123",
      session_id: "sess123",
      url: "https://example.com/?utm_source=google&utm_medium=cpc"
    )
  end

  def stub_session_success
    response = {
      "status" => "accepted",
      "visitor_id" => "vis_abc123",
      "session_id" => "sess_xyz789",
      "channel" => "paid_search"
    }
    Mbuzz::Api.stub(:post_with_response, response) do
      yield
    end
  end

  def stub_session_failure
    Mbuzz::Api.stub(:post_with_response, nil) do
      yield
    end
  end
end
