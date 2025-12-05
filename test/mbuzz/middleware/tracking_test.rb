# frozen_string_literal: true

require "test_helper"

class Mbuzz::Middleware::TrackingTest < Minitest::Test
  def setup
    @original_config = Mbuzz.instance_variable_get(:@config)
    Mbuzz.instance_variable_set(:@config, nil)

    Mbuzz.configure do |config|
      config.api_key = "sk_test_123"
      config.api_url = "https://mbuzz.co/api/v1"
    end

    @app = ->(env) { [200, { "Content-Type" => "text/html" }, ["OK"]] }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)
  end

  def teardown
    Mbuzz.instance_variable_set(:@config, @original_config)
    Thread.current[:mbuzz_request] = nil
  end

  def test_calls_next_middleware
    status, _headers, body = call_result
    assert_equal 200, status
    assert_equal ["OK"], body
  end

  def test_sets_request_context_during_request
    context_was_set = false

    @app = ->(env) {
      context_was_set = !Mbuzz::RequestContext.current.nil?
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    call_result
    assert context_was_set
  end

  def test_clears_request_context_after_request
    call_result
    assert_nil Mbuzz::RequestContext.current
  end

  def test_generates_visitor_id_when_missing
    _status, headers, _body = call_result

    cookie_header = Array(headers["set-cookie"]).join("\n")
    refute_nil cookie_header
    assert_match(/_mbuzz_vid=/, cookie_header)
  end

  def test_preserves_existing_visitor_id
    @existing_visitor_id = "existing123"
    _status, headers, _body = call_result

    cookie_header = Array(headers["set-cookie"]).join("\n")
    assert_match(/_mbuzz_vid=existing123/, cookie_header)
  end

  def test_extracts_user_id_from_session
    @session = { "user_id" => 456 }

    captured_user_id = nil
    @app = ->(env) {
      captured_user_id = env["mbuzz.user_id"]
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    call_result
    assert_equal 456, captured_user_id
  end

  def test_extracts_visitor_id_from_cookie
    @existing_visitor_id = "visitor789"

    captured_visitor_id = nil
    @app = ->(env) {
      captured_visitor_id = env["mbuzz.visitor_id"]
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    call_result
    assert_equal "visitor789", captured_visitor_id
  end

  # Session cookie tests

  def test_generates_session_id_when_missing
    _status, headers, _body = call_result

    cookie_header = Array(headers["set-cookie"]).join("\n")
    refute_nil cookie_header
    assert_match(/_mbuzz_sid=/, cookie_header)
  end

  def test_preserves_existing_session_id
    @existing_session_id = "session123abc"
    _status, headers, _body = call_result

    cookie_header = Array(headers["set-cookie"]).join("\n")
    assert_match(/_mbuzz_sid=session123abc/, cookie_header)
  end

  def test_extracts_session_id_from_cookie
    @existing_session_id = "session789xyz"

    captured_session_id = nil
    @app = ->(env) {
      captured_session_id = env["mbuzz.session_id"]
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    call_result
    assert_equal "session789xyz", captured_session_id
  end

  def test_sets_session_id_in_env
    captured_session_id = nil
    @app = ->(env) {
      captured_session_id = env["mbuzz.session_id"]
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    call_result
    refute_nil captured_session_id
    assert_equal 64, captured_session_id.length
  end

  def test_creates_session_on_new_visit
    session_created = false

    Mbuzz::Client.stub(:session, ->(**args) { session_created = true; true }) do
      call_result
      sleep 0.1 # Allow thread to execute
    end

    assert session_created, "Session should be created for new visitors"
  end

  def test_does_not_create_session_on_existing_session
    @existing_session_id = "existing_session"
    session_created = false

    Mbuzz::Client.stub(:session, ->(**args) { session_created = true; true }) do
      call_result
      sleep 0.1
    end

    refute session_created, "Session should not be created for existing sessions"
  end

  def test_session_creation_failure_does_not_break_request
    Mbuzz::Client.stub(:session, ->(**args) { raise "API Error" }) do
      status, _headers, body = call_result
      sleep 0.1

      assert_equal 200, status
      assert_equal ["OK"], body
    end
  end

  # Path filtering tests

  def test_skips_health_check_paths
    @path_info = "/up"
    assert @middleware.skip_request?(build_env)

    @path_info = "/health"
    assert @middleware.skip_request?(build_env)

    @path_info = "/healthz"
    assert @middleware.skip_request?(build_env)

    @path_info = "/ping"
    assert @middleware.skip_request?(build_env)
  end

  def test_skips_asset_paths
    @path_info = "/assets/application.js"
    assert @middleware.skip_request?(build_env)

    @path_info = "/packs/bundle.js"
    assert @middleware.skip_request?(build_env)

    @path_info = "/cable"
    assert @middleware.skip_request?(build_env)
  end

  def test_skips_static_asset_extensions
    @path_info = "/some/file.js"
    assert @middleware.skip_request?(build_env)

    @path_info = "/some/style.css"
    assert @middleware.skip_request?(build_env)

    @path_info = "/images/logo.png"
    assert @middleware.skip_request?(build_env)

    @path_info = "/fonts/roboto.woff2"
    assert @middleware.skip_request?(build_env)
  end

  def test_does_not_skip_normal_page_requests
    @path_info = "/products"
    refute @middleware.skip_request?(build_env)

    @path_info = "/orders/123"
    refute @middleware.skip_request?(build_env)

    @path_info = "/"
    refute @middleware.skip_request?(build_env)
  end

  def test_skipped_requests_do_not_set_cookies
    @path_info = "/up"

    _status, headers, _body = @middleware.call(build_env)

    # Headers should not contain mbuzz cookies
    cookie_header = Array(headers["set-cookie"]).join("\n")
    refute_match(/_mbuzz_vid=/, cookie_header)
    refute_match(/_mbuzz_sid=/, cookie_header)
  end

  def test_skipped_requests_do_not_create_sessions
    @path_info = "/health"
    session_created = false

    Mbuzz::Client.stub(:session, ->(**args) { session_created = true; true }) do
      @middleware.call(build_env)
      sleep 0.1
    end

    refute session_created, "Session should not be created for health check requests"
  end

  def test_custom_skip_paths
    Mbuzz.config.skip_paths = ["/admin", "/internal"]

    @path_info = "/admin/dashboard"
    assert @middleware.skip_request?(build_env)

    @path_info = "/internal/metrics"
    assert @middleware.skip_request?(build_env)

    # But normal paths still work
    @path_info = "/products"
    refute @middleware.skip_request?(build_env)
  end

  def test_custom_skip_extensions
    Mbuzz.config.skip_extensions = [".pdf", ".xml"]

    @path_info = "/documents/report.pdf"
    assert @middleware.skip_request?(build_env)

    @path_info = "/feeds/sitemap.xml"
    assert @middleware.skip_request?(build_env)
  end

  def test_path_filtering_is_case_insensitive
    @path_info = "/UP"
    assert @middleware.skip_request?(build_env)

    @path_info = "/HEALTH"
    assert @middleware.skip_request?(build_env)

    @path_info = "/Assets/Application.JS"
    assert @middleware.skip_request?(build_env)
  end

  private

  def call_result
    @call_result ||= @middleware.call(build_env)
  end

  def build_env
    env = {
      "REQUEST_METHOD" => @request_method || "GET",
      "PATH_INFO" => @path_info || "/products",
      "QUERY_STRING" => @query_string || "utm_source=google",
      "HTTP_REFERER" => @http_referer || "https://google.com",
      "HTTP_USER_AGENT" => @http_user_agent || "Mozilla/5.0",
      "rack.url_scheme" => @rack_url_scheme || "https",
      "HTTP_HOST" => @http_host || "example.com",
      "rack.session" => @session || {}
    }

    cookies = []
    cookies << "_mbuzz_vid=#{@existing_visitor_id}" if @existing_visitor_id
    cookies << "_mbuzz_sid=#{@existing_session_id}" if @existing_session_id
    env["HTTP_COOKIE"] = cookies.join("; ") if cookies.any?

    env
  end
end
