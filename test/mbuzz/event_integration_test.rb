# frozen_string_literal: true

require "test_helper"

class Mbuzz::EventIntegrationTest < Minitest::Test
  def setup
    @original_config = Mbuzz.instance_variable_get(:@config)
    Mbuzz.instance_variable_set(:@config, nil)

    Mbuzz.configure do |config|
      config.api_key = "sk_test_123"
      config.api_url = "https://mbuzz.co/api/v1"
    end

    @captured_params = nil
  end

  def teardown
    Mbuzz.instance_variable_set(:@config, @original_config)
    Thread.current[:mbuzz_request] = nil
  end

  # Server-side session resolution tests (v1.3.0+)
  # Mbuzz.event should forward ip and user_agent from RequestContext

  def test_event_passes_ip_from_request_context
    request = build_mock_request(
      ip: "203.0.113.50",
      user_agent: "Mozilla/5.0"
    )

    stub_client_track do
      Mbuzz::RequestContext.with_context(request: request) do
        Mbuzz.event("page_view")
      end
    end

    assert_equal "203.0.113.50", @captured_params[:ip]
  end

  def test_event_passes_user_agent_from_request_context
    request = build_mock_request(
      ip: "203.0.113.50",
      user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
    )

    stub_client_track do
      Mbuzz::RequestContext.with_context(request: request) do
        Mbuzz.event("page_view")
      end
    end

    assert_equal "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", @captured_params[:user_agent]
  end

  def test_event_passes_both_ip_and_user_agent
    request = build_mock_request(
      ip: "10.0.0.1",
      user_agent: "Chrome/120"
    )

    stub_client_track do
      Mbuzz::RequestContext.with_context(request: request) do
        Mbuzz.event("signup", plan: "pro")
      end
    end

    assert_equal "10.0.0.1", @captured_params[:ip]
    assert_equal "Chrome/120", @captured_params[:user_agent]
  end

  def test_event_passes_nil_ip_and_user_agent_without_context
    stub_client_track do
      # No RequestContext - simulates background job or direct call
      Mbuzz.event("background_task")
    end

    assert_nil @captured_params[:ip]
    assert_nil @captured_params[:user_agent]
  end

  def test_event_extracts_ip_from_x_forwarded_for
    request = build_mock_request(
      ip: "192.168.1.1",
      user_agent: "Mozilla/5.0",
      env: { "HTTP_X_FORWARDED_FOR" => "203.0.113.99, 10.0.0.1" }
    )

    stub_client_track do
      Mbuzz::RequestContext.with_context(request: request) do
        Mbuzz.event("page_view")
      end
    end

    # Should use X-Forwarded-For, not direct IP
    assert_equal "203.0.113.99", @captured_params[:ip]
  end

  private

  def build_mock_request(ip:, user_agent:, env: {})
    MockRequest.new(
      url: "https://example.com/page",
      referrer: "https://google.com",
      user_agent: user_agent,
      env: env,
      ip: ip
    )
  end

  def stub_client_track
    Mbuzz::Client.stub(:track, ->(**params) {
      @captured_params = params
      { success: true, event_id: "evt_test123" }
    }) do
      yield
    end
  end

  class MockRequest
    attr_reader :url, :referrer, :user_agent, :env, :ip

    def initialize(url:, referrer:, user_agent:, env: {}, ip: nil)
      @url = url
      @referrer = referrer
      @user_agent = user_agent
      @env = env
      @ip = ip
    end
  end
end
