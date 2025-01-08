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

  # Server-side session resolution - no session cookie needed
  def test_does_not_set_session_cookie
    _status, headers, _body = call_result

    cookie_header = Array(headers["set-cookie"]).join("\n")
    refute_match(/_mbuzz_sid=/, cookie_header, "Should not set session cookie (server-side resolution)")
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

  # Request isolation tests - visitor IDs must not leak across requests

  def test_generates_different_visitor_ids_for_different_requests_without_cookies
    # First request - no cookies, should generate new visitor_id
    env1 = build_env_without_cookies
    _status1, headers1, _body1 = @middleware.call(env1)
    visitor_id_1 = extract_cookie_value(headers1, "_mbuzz_vid")

    # Second request - no cookies, should generate DIFFERENT visitor_id
    env2 = build_env_without_cookies
    _status2, headers2, _body2 = @middleware.call(env2)
    visitor_id_2 = extract_cookie_value(headers2, "_mbuzz_vid")

    refute_nil visitor_id_1, "First request should generate visitor_id"
    refute_nil visitor_id_2, "Second request should generate visitor_id"
    refute_equal visitor_id_1, visitor_id_2, "Different requests without cookies should get different visitor_ids"
  end

  def test_visitor_id_from_cookie_not_leaked_to_next_request
    # First request WITH visitor cookie
    @existing_visitor_id = "user_a_visitor_id"
    env1 = build_env
    _status1, headers1, _body1 = @middleware.call(env1)
    visitor_id_1 = extract_cookie_value(headers1, "_mbuzz_vid")

    # Second request WITHOUT cookies (different user)
    env2 = build_env_without_cookies
    _status2, headers2, _body2 = @middleware.call(env2)
    visitor_id_2 = extract_cookie_value(headers2, "_mbuzz_vid")

    assert_equal "user_a_visitor_id", visitor_id_1
    refute_equal "user_a_visitor_id", visitor_id_2, "User A's visitor_id should not leak to User B's request"
  end

  def test_env_visitor_id_isolated_between_requests
    captured_visitor_ids = []

    @app = ->(env) {
      captured_visitor_ids << env["mbuzz.visitor_id"]
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    # Two requests without cookies
    @middleware.call(build_env_without_cookies)
    @middleware.call(build_env_without_cookies)

    assert_equal 2, captured_visitor_ids.length
    refute_equal captured_visitor_ids[0], captured_visitor_ids[1],
      "env['mbuzz.visitor_id'] should be different for each request without cookies"
  end

  # Thread-safety tests - middleware must handle concurrent requests correctly

  def test_concurrent_requests_get_isolated_visitor_ids
    captured_data = Queue.new
    barrier = Queue.new

    @app = ->(env) {
      visitor_id = env["mbuzz.visitor_id"]
      captured_data << { visitor_id: visitor_id, thread: Thread.current.object_id }
      barrier.pop
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    threads = 2.times.map do
      Thread.new { @middleware.call(build_env_without_cookies) }
    end

    sleep 0.1
    2.times { barrier << :go }
    threads.each(&:join)

    results = []
    results << captured_data.pop until captured_data.empty?

    assert_equal 2, results.length
    visitor_ids = results.map { |r| r[:visitor_id] }
    assert_equal 2, visitor_ids.uniq.length,
      "Concurrent requests should get different visitor_ids, got: #{visitor_ids.inspect}"
  end

  def test_concurrent_requests_set_correct_cookies
    results = Queue.new

    @app = ->(env) { [200, {}, ["OK"]] }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    # 10 concurrent requests
    threads = 10.times.map do |i|
      Thread.new do
        env = build_env_without_cookies.merge("HTTP_USER_AGENT" => "Browser#{i}")
        _status, headers, _body = @middleware.call(env)

        visitor_id_in_env = env["mbuzz.visitor_id"]
        visitor_id_in_cookie = extract_cookie_value(headers, "_mbuzz_vid")

        results << {
          env_visitor_id: visitor_id_in_env,
          cookie_visitor_id: visitor_id_in_cookie,
          match: visitor_id_in_env == visitor_id_in_cookie
        }
      end
    end

    threads.each(&:join)

    all_results = []
    all_results << results.pop until results.empty?

    mismatches = all_results.reject { |r| r[:match] }
    assert mismatches.empty?,
      "All requests should have matching env and cookie visitor_ids. Mismatches: #{mismatches.inspect}"

    # Verify all visitor_ids are unique
    visitor_ids = all_results.map { |r| r[:env_visitor_id] }
    assert_equal 10, visitor_ids.uniq.length,
      "All 10 concurrent requests should get unique visitor_ids"
  end

  private

  def build_env_without_cookies
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/products",
      "QUERY_STRING" => "",
      "HTTP_REFERER" => "https://google.com",
      "HTTP_USER_AGENT" => "Mozilla/5.0",
      "rack.url_scheme" => "https",
      "HTTP_HOST" => "example.com",
      "rack.session" => {}
    }
  end

  def extract_cookie_value(headers, cookie_name)
    cookie_header = Array(headers["set-cookie"]).join("\n")
    match = cookie_header.match(/#{cookie_name}=([^;]+)/)
    match ? match[1] : nil
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
    env["HTTP_COOKIE"] = cookies.join("; ") if cookies.any?

    env
  end
end
