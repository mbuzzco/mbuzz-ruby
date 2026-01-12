# frozen_string_literal: true

require "active_support"
require "active_support/current_attributes"
require "test_helper"
require "mbuzz/current"

class CurrentAttributesTest < Minitest::Test
  def setup
    Mbuzz::Current.reset
  end

  def teardown
    Mbuzz::Current.reset
  end

  # ============================================================================
  # Mbuzz::Current stores context for background jobs
  # ============================================================================

  def test_current_stores_visitor_id
    Mbuzz::Current.visitor_id = "vis_abc123"

    assert_equal "vis_abc123", Mbuzz::Current.visitor_id
  end

  def test_current_stores_user_id
    Mbuzz::Current.user_id = "user_456"

    assert_equal "user_456", Mbuzz::Current.user_id
  end

  def test_current_stores_ip
    Mbuzz::Current.ip = "203.0.113.50"

    assert_equal "203.0.113.50", Mbuzz::Current.ip
  end

  def test_current_stores_user_agent
    Mbuzz::Current.user_agent = "Mozilla/5.0 Test"

    assert_equal "Mozilla/5.0 Test", Mbuzz::Current.user_agent
  end

  def test_current_reset_clears_all_attributes
    Mbuzz::Current.visitor_id = "vis_abc123"
    Mbuzz::Current.user_id = "user_456"
    Mbuzz::Current.ip = "203.0.113.50"
    Mbuzz::Current.user_agent = "Mozilla/5.0"

    Mbuzz::Current.reset

    assert_nil Mbuzz::Current.visitor_id
    assert_nil Mbuzz::Current.user_id
    assert_nil Mbuzz::Current.ip
    assert_nil Mbuzz::Current.user_agent
  end

  # ============================================================================
  # Mbuzz.visitor_id reads from Current (for background jobs)
  # ============================================================================

  def test_visitor_id_returns_from_current_when_set
    Mbuzz::Current.visitor_id = "vis_from_current"

    assert_equal "vis_from_current", Mbuzz.visitor_id
  end

  def test_visitor_id_returns_nil_when_current_not_set_and_no_request
    assert_nil Mbuzz.visitor_id
  end

  # ============================================================================
  # Mbuzz.event uses Current.visitor_id in background jobs
  # ============================================================================

  def test_event_uses_visitor_id_from_current
    stub_config

    Mbuzz::Current.visitor_id = "vis_background_job"
    Mbuzz::Current.ip = "10.0.0.1"
    Mbuzz::Current.user_agent = "BackgroundWorker/1.0"

    captured_params = nil
    Mbuzz::Client.stub :track, ->(params) { captured_params = params; { id: "evt_123" } } do
      result = Mbuzz.event("order_processed", order_id: "ORD-789")

      assert result
      assert_equal "vis_background_job", captured_params[:visitor_id]
      assert_equal "10.0.0.1", captured_params[:ip]
      assert_equal "BackgroundWorker/1.0", captured_params[:user_agent]
    end
  end

  def test_conversion_uses_visitor_id_from_current
    stub_config

    Mbuzz::Current.visitor_id = "vis_background_job"
    Mbuzz::Current.ip = "10.0.0.1"
    Mbuzz::Current.user_agent = "BackgroundWorker/1.0"

    captured_params = nil
    Mbuzz::Client.stub :conversion, ->(params) { captured_params = params; { id: "conv_123" } } do
      result = Mbuzz.conversion("purchase", revenue: 99.99)

      assert result
      assert_equal "vis_background_job", captured_params[:visitor_id]
      assert_equal "10.0.0.1", captured_params[:ip]
      assert_equal "BackgroundWorker/1.0", captured_params[:user_agent]
    end
  end

  def test_explicit_visitor_id_overrides_current
    stub_config

    Mbuzz::Current.visitor_id = "vis_from_current"

    captured_params = nil
    Mbuzz::Client.stub :track, ->(params) { captured_params = params; { id: "evt_123" } } do
      Mbuzz.event("test", visitor_id: "vis_explicit")

      assert_equal "vis_explicit", captured_params[:visitor_id]
    end
  end

  # ============================================================================
  # Middleware stores context in Current for background jobs
  # ============================================================================

  def test_middleware_stores_visitor_id_in_current
    app = ->(env) {
      # During request, Current should have visitor_id
      assert_equal env["mbuzz.visitor_id"], Mbuzz::Current.visitor_id
      [200, {}, ["OK"]]
    }
    middleware = Mbuzz::Middleware::Tracking.new(app)

    middleware.call(build_env)
  end

  def test_middleware_stores_ip_in_current
    app = ->(env) {
      assert_equal "203.0.113.50", Mbuzz::Current.ip
      [200, {}, ["OK"]]
    }
    middleware = Mbuzz::Middleware::Tracking.new(app)

    middleware.call(build_env_with_ip)
  end

  def test_middleware_stores_user_agent_in_current
    app = ->(env) {
      assert_equal "Mozilla/5.0 Test", Mbuzz::Current.user_agent
      [200, {}, ["OK"]]
    }
    middleware = Mbuzz::Middleware::Tracking.new(app)

    middleware.call(build_env_with_user_agent)
  end

  def test_middleware_resets_current_after_request
    app = ->(_env) { [200, {}, ["OK"]] }
    middleware = Mbuzz::Middleware::Tracking.new(app)

    middleware.call(build_env)

    # After request, Current should be reset
    assert_nil Mbuzz::Current.visitor_id
    assert_nil Mbuzz::Current.ip
    assert_nil Mbuzz::Current.user_agent
  end

  private

  def stub_config
    Mbuzz.config.api_key = "sk_test_abc123"
    Mbuzz.config.api_url = "https://test.mbuzz.co/api/v1"
  end

  def build_env
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/products",
      "QUERY_STRING" => "",
      "HTTP_USER_AGENT" => "Mozilla/5.0",
      "rack.url_scheme" => "https",
      "HTTP_HOST" => "example.com",
      "rack.session" => {}
    }
  end

  def build_env_with_ip
    build_env.merge("HTTP_X_FORWARDED_FOR" => "203.0.113.50")
  end

  def build_env_with_user_agent
    build_env.merge("HTTP_USER_AGENT" => "Mozilla/5.0 Test")
  end
end
