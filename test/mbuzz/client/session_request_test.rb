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

  # The visitor's IP, which mbuzz needs for Meta's `client_ip_address` — Meta
  # documents it as required for website events.
  #
  # It was computed by the middleware (it is half of
  # `device_fingerprint = SHA256(ip|user_agent)`) and then DROPPED here until
  # 2026-09-17: `Client.session` had no `ip:` keyword and this payload omitted
  # it. Found by the SDK integration harness, not by a unit test, because every
  # layer was correct on its own. These pin it so it cannot be dropped again.

  def test_payload_includes_the_visitor_ip
    payload = captured_payload(ip: "203.0.113.45")

    assert_equal "203.0.113.45", payload[:session][:ip]
  end

  def test_payload_omits_ip_when_none_was_given
    assert_nil captured_payload[:session][:ip]
  end

  def test_client_session_passes_the_ip_through
    captured = nil
    Mbuzz::Api.stub(:post_with_response, ->(_path, body) { captured = body; nil }) do
      Mbuzz::Client.session(
        visitor_id: "vis123", session_id: "sess123",
        url: "https://example.com/", ip: "203.0.113.45"
      )
    end

    assert_equal "203.0.113.45", captured[:session][:ip]
  end

  private

  # The body actually handed to Api.post_with_response. Asserting on the real
  # posted body rather than on a private method is what makes these regression
  # guards rather than restatements of the implementation.
  def captured_payload(**overrides)
    captured = nil
    Mbuzz::Api.stub(:post_with_response, ->(_path, body) { captured = body; nil }) do
      Mbuzz::Client::SessionRequest.new(
        visitor_id: "vis123", session_id: "sess123",
        url: "https://example.com/", **overrides
      ).call
    end
    captured
  end

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
