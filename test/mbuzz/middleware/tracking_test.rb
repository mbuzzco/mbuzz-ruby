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

  def test_session_cookie_not_set
    _status, headers, _body = call_result

    cookie_header = Array(headers["set-cookie"]).join("\n")
    refute_match(/_mbuzz_sid=/, cookie_header, "Should not set session cookie — sessions are server-side")
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

# Session creation tests - middleware must call /api/v1/sessions for new visitors
class Mbuzz::Middleware::SessionCreationTest < Minitest::Test
  def setup
    @original_config = Mbuzz.instance_variable_get(:@config)
    Mbuzz.instance_variable_set(:@config, nil)

    Mbuzz.configure do |config|
      config.api_key = "sk_test_123"
      config.api_url = "https://mbuzz.co/api/v1"
    end

    @app = ->(env) { [200, { "Content-Type" => "text/html" }, ["OK"]] }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)
    @session_created = false
  end

  def teardown
    Mbuzz.instance_variable_set(:@config, @original_config)
  end

  # Session creation tests

  def test_creates_session_for_new_visitor
    session_created = false

    stub_session_creation(-> { session_created = true }) do
      @middleware.call(build_env_without_cookies)
    end

    assert session_created, "Middleware should create session for new visitor"
  end

  def test_creates_session_for_returning_visitor_navigating
    session_created = false

    stub_session_creation(-> { session_created = true }) do
      env = build_env_with_visitor_only
      @middleware.call(env)
    end

    assert session_created, "Middleware should create session for returning visitor on navigation"
  end

  def test_session_creation_includes_url
    captured_params = nil

    stub_session_creation_capture(->(params) { captured_params = params }) do
      env = build_env_without_cookies
      @middleware.call(env)
    end

    refute_nil captured_params, "Session should be created"
    assert_match(%r{example\.com}, captured_params[:url].to_s)
  end

  def test_session_creation_includes_referrer
    captured_params = nil

    stub_session_creation_capture(->(params) { captured_params = params }) do
      env = build_env_without_cookies.merge("HTTP_REFERER" => "https://google.com/search")
      @middleware.call(env)
    end

    refute_nil captured_params
    assert_equal "https://google.com/search", captured_params[:referrer]
  end

  def test_session_creation_includes_device_fingerprint
    captured_params = nil

    stub_session_creation_capture(->(params) { captured_params = params }) do
      env = build_env_without_cookies.merge(
        "HTTP_X_FORWARDED_FOR" => "192.168.1.100",
        "HTTP_USER_AGENT" => "Mozilla/5.0"
      )
      @middleware.call(env)
    end

    refute_nil captured_params
    refute_nil captured_params[:device_fingerprint], "Should include device fingerprint"
    assert_equal 32, captured_params[:device_fingerprint].length
  end

  def test_session_cookie_not_set
    stub_session_creation_success do
      _status, headers, _body = @middleware.call(build_env_without_cookies)

      cookie_header = Array(headers["set-cookie"]).join("\n")
      refute_match(/_mbuzz_sid=/, cookie_header, "Should not set session cookie — sessions are server-side")
    end
  end

  def test_session_creation_does_not_block_request
    # Session creation should be async/non-blocking
    request_completed = false
    @app = ->(env) {
      request_completed = true
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    # Simulate slow session creation
    stub_slow_session_creation do
      start = Time.now
      @middleware.call(build_env_without_cookies)
      elapsed = Time.now - start

      assert request_completed, "Request should complete"
      # If blocking, would take > 1 second; async should be fast
      assert elapsed < 0.5, "Session creation should not block request (took #{elapsed}s)"
    end
  end

  def test_session_creation_failure_does_not_crash_app
    @app = ->(env) { [200, {}, ["OK"]] }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    stub_session_creation_error do
      status, _headers, body = @middleware.call(build_env_without_cookies)

      assert_equal 200, status, "Request should succeed even if session creation fails"
      assert_equal ["OK"], body
    end
  end

  def test_skipped_requests_do_not_create_sessions
    session_created = false

    stub_session_creation(-> { session_created = true }) do
      env = build_env_without_cookies.merge("PATH_INFO" => "/up")
      @middleware.call(env)
    end

    refute session_created, "Health check requests should not create sessions"
  end

  # Thread-safety tests for async session creation
  # The middleware starts a background thread to create sessions.
  # Request data must be captured BEFORE the thread starts, not accessed
  # from the request object inside the thread.

  def test_async_session_creation_captures_request_data_before_thread_starts
    # This test exposes a race condition: if the background thread accesses
    # the request object after the main request completes, it may get nil/stale data.
    captured_params = nil
    request_completed = false

    # Stub to capture what session creation receives
    Mbuzz::Client::SessionRequest.stub(:new, ->(**params) {
      # Wait until main request is done - simulates slow thread startup
      sleep 0.1 while !request_completed
      captured_params = params
      mock = Minitest::Mock.new
      mock.expect(:call, { success: true, visitor_id: "v", session_id: "s", channel: "direct" })
      mock
    }) do
      env = build_env_without_cookies.merge(
        "HTTP_REFERER" => "https://google.com/search?q=test",
        "HTTP_USER_AGENT" => "TestBrowser/1.0",
        "HTTP_X_FORWARDED_FOR" => "203.0.113.42"
      )

      @middleware.call(env)
      request_completed = true

      # Wait for background thread to complete
      sleep 0.3
    end

    # The session creation should have received the correct data
    # even though the main request completed before the thread ran
    refute_nil captured_params, "Session creation should have been called"
    assert_match(%r{example\.com}, captured_params[:url].to_s, "URL should be captured")
    assert_equal "https://google.com/search?q=test", captured_params[:referrer], "Referrer should be captured"
    refute_nil captured_params[:device_fingerprint], "Device fingerprint should be captured"
    assert_equal 32, captured_params[:device_fingerprint].length, "Fingerprint should be 32 chars"
  end

  def test_async_session_creation_has_correct_fingerprint_when_request_object_invalid
    # Simulates the scenario where the request object is invalidated
    # after the main request completes
    captured_fingerprints = []

    Mbuzz::Client::SessionRequest.stub(:new, ->(**params) {
      captured_fingerprints << params[:device_fingerprint]
      mock = Minitest::Mock.new
      mock.expect(:call, { success: true, visitor_id: "v", session_id: "s", channel: "direct" })
      mock
    }) do
      env = build_env_without_cookies.merge(
        "HTTP_USER_AGENT" => "UniqueAgent/123",
        "HTTP_X_FORWARDED_FOR" => "198.51.100.99"
      )

      @middleware.call(env)
      sleep 0.2  # Wait for async thread
    end

    refute captured_fingerprints.empty?, "Should have captured fingerprint"
    fingerprint = captured_fingerprints.first
    refute_nil fingerprint, "Fingerprint should not be nil"

    # Verify it's the expected fingerprint for our IP + User Agent
    expected = Digest::SHA256.hexdigest("198.51.100.99|UniqueAgent/123")[0, 32]
    assert_equal expected, fingerprint, "Fingerprint should match expected value"
  end

  def test_async_session_creation_not_affected_by_env_mutation_after_request
    # This is the critical test: in production, the env hash may be mutated or
    # cleared after the response is sent. The background thread must NOT read
    # from the request/env after the main request completes.
    #
    # We simulate this by mutating the env after the middleware call returns
    # but before the background thread reads it.
    captured_params = nil
    thread_started = Queue.new
    can_continue = Queue.new

    Mbuzz::Client::SessionRequest.stub(:new, ->(**params) {
      thread_started << true
      can_continue.pop  # Wait for signal
      captured_params = params
      mock = Minitest::Mock.new
      mock.expect(:call, { success: true, visitor_id: "v", session_id: "s", channel: "direct" })
      mock
    }) do
      env = build_env_without_cookies.merge(
        "HTTP_REFERER" => "https://original-referrer.com",
        "HTTP_USER_AGENT" => "OriginalAgent/1.0",
        "HTTP_X_FORWARDED_FOR" => "10.0.0.1"
      )

      @middleware.call(env)

      # Wait for background thread to start
      thread_started.pop

      # Mutate the env - simulating what happens in production when
      # the request is reused or cleared
      env["HTTP_REFERER"] = "https://MUTATED-referrer.com"
      env["HTTP_USER_AGENT"] = "MUTATED-Agent"
      env["HTTP_X_FORWARDED_FOR"] = "MUTATED-IP"

      # Let background thread continue
      can_continue << true

      # Wait for thread to complete
      sleep 0.2
    end

    refute_nil captured_params, "Session creation should have been called"

    # These assertions will FAIL if the bug exists (reading from request in thread)
    # They will PASS after the fix (reading from captured context)
    assert_equal "https://original-referrer.com", captured_params[:referrer],
      "Referrer should be original value, not mutated - data must be captured before thread starts"

    expected_fingerprint = Digest::SHA256.hexdigest("10.0.0.1|OriginalAgent/1.0")[0, 32]
    assert_equal expected_fingerprint, captured_params[:device_fingerprint],
      "Fingerprint should use original IP/UA, not mutated - data must be captured before thread starts"
  end

  def test_context_contains_all_session_creation_data
    # The context hash must contain ALL data needed for session creation
    # so that the background thread doesn't need to access the request object.
    # This is critical for thread-safety in production where requests are recycled.
    captured_context = nil

    # Monkey-patch to capture the context
    original_method = @middleware.method(:build_request_context)
    @middleware.define_singleton_method(:build_request_context) do |request|
      ctx = original_method.call(request)
      captured_context = ctx
      ctx
    end

    stub_session_creation_success do
      env = build_env_without_cookies.merge(
        "HTTP_REFERER" => "https://google.com/search",
        "HTTP_USER_AGENT" => "TestBrowser/2.0",
        "HTTP_X_FORWARDED_FOR" => "192.168.1.100"
      )
      @middleware.call(env)
    end

    refute_nil captured_context, "Context should be captured"

    # Verify context contains session creation data (not just visitor/session IDs)
    assert captured_context.key?(:url), "Context must contain :url for async session creation"
    assert captured_context.key?(:referrer), "Context must contain :referrer for async session creation"
    assert captured_context.key?(:device_fingerprint), "Context must contain :device_fingerprint for async session creation"

    # Verify the values are correct
    assert_match(%r{example\.com}, captured_context[:url].to_s) if captured_context[:url]
    assert_equal "https://google.com/search", captured_context[:referrer] if captured_context[:referrer]

    if captured_context[:device_fingerprint]
      expected_fp = Digest::SHA256.hexdigest("192.168.1.100|TestBrowser/2.0")[0, 32]
      assert_equal expected_fp, captured_context[:device_fingerprint]
    end
  end

  private

  def navigation_headers
    {
      "HTTP_SEC_FETCH_MODE" => "navigate",
      "HTTP_SEC_FETCH_DEST" => "document"
    }
  end

  def build_env_without_cookies
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/products",
      "QUERY_STRING" => "utm_source=google&utm_medium=cpc",
      "HTTP_REFERER" => "https://google.com",
      "HTTP_USER_AGENT" => "Mozilla/5.0",
      "rack.url_scheme" => "https",
      "HTTP_HOST" => "example.com",
      "rack.session" => {}
    }.merge(navigation_headers)
  end

  def build_env_with_visitor_only
    build_env_without_cookies.merge(
      "HTTP_COOKIE" => "_mbuzz_vid=existing_visitor_123"
    )
  end

  def stub_session_creation(callback)
    # Stub the session creation to track if it was called
    # Note: Must wait for async thread inside the block, before stub is removed
    Mbuzz::Client::SessionRequest.stub(:new, ->(**_params) {
      callback.call
      mock = Minitest::Mock.new
      mock.expect(:call, { success: true, visitor_id: "v", session_id: "s", channel: "direct" })
      mock
    }) do
      yield
      sleep 0.1  # Wait for async thread to complete
    end
  end

  def stub_session_creation_capture(callback)
    # Note: Must wait for async thread inside the block, before stub is removed
    Mbuzz::Client::SessionRequest.stub(:new, ->(**params) {
      callback.call(params)
      mock = Minitest::Mock.new
      mock.expect(:call, { success: true, visitor_id: "v", session_id: "s", channel: "direct" })
      mock
    }) do
      yield
      sleep 0.1  # Wait for async thread to complete
    end
  end

  def stub_session_creation_success
    response = { "status" => "accepted", "visitor_id" => "v", "session_id" => "s", "channel" => "direct" }
    Mbuzz::Api.stub(:post_with_response, response) do
      yield
    end
  end

  def stub_slow_session_creation
    Mbuzz::Api.stub(:post_with_response, ->(*) {
      sleep 1.5  # Simulate slow API
      { "status" => "accepted", "visitor_id" => "v", "session_id" => "s", "channel" => "direct" }
    }) do
      yield
    end
  end

  def stub_session_creation_error
    Mbuzz::Api.stub(:post_with_response, ->(*) { raise StandardError, "API Error" }) do
      yield
    end
  end
end

# Navigation detection tests — should_create_session? gates session creation
# on Sec-Fetch-* headers (whitelist) with framework-specific blacklist fallback.
class Mbuzz::Middleware::NavigationDetectionTest < Minitest::Test
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
  end

  # === Whitelist: Sec-Fetch-* headers present (modern browsers) ===

  def test_creates_session_for_real_page_navigation
    env = base_env.merge(
      "HTTP_SEC_FETCH_MODE" => "navigate",
      "HTTP_SEC_FETCH_DEST" => "document"
    )

    assert @middleware.should_create_session?(env)
  end

  def test_skips_session_for_turbo_frame
    env = base_env.merge(
      "HTTP_SEC_FETCH_MODE" => "same-origin",
      "HTTP_SEC_FETCH_DEST" => "empty",
      "HTTP_TURBO_FRAME" => "content"
    )

    refute @middleware.should_create_session?(env)
  end

  def test_skips_session_for_htmx_request
    env = base_env.merge(
      "HTTP_SEC_FETCH_MODE" => "same-origin",
      "HTTP_SEC_FETCH_DEST" => "empty",
      "HTTP_HX_REQUEST" => "true"
    )

    refute @middleware.should_create_session?(env)
  end

  def test_skips_session_for_fetch_xhr
    env = base_env.merge(
      "HTTP_SEC_FETCH_MODE" => "cors",
      "HTTP_SEC_FETCH_DEST" => "empty"
    )

    refute @middleware.should_create_session?(env)
  end

  def test_skips_session_for_prefetch
    env = base_env.merge(
      "HTTP_SEC_FETCH_MODE" => "navigate",
      "HTTP_SEC_FETCH_DEST" => "document",
      "HTTP_SEC_PURPOSE" => "prefetch"
    )

    refute @middleware.should_create_session?(env)
  end

  def test_skips_session_for_iframe
    env = base_env.merge(
      "HTTP_SEC_FETCH_MODE" => "navigate",
      "HTTP_SEC_FETCH_DEST" => "iframe"
    )

    refute @middleware.should_create_session?(env)
  end

  # === Blacklist fallback: no Sec-Fetch-* headers (old browsers / bots) ===

  def test_creates_session_for_old_browser_without_framework_headers
    env = base_env # No Sec-Fetch-*, no framework headers

    assert @middleware.should_create_session?(env)
  end

  def test_skips_session_for_old_browser_with_turbo_frame
    env = base_env.merge("HTTP_TURBO_FRAME" => "content")

    refute @middleware.should_create_session?(env)
  end

  def test_skips_session_for_old_browser_with_hx_request
    env = base_env.merge("HTTP_HX_REQUEST" => "true")

    refute @middleware.should_create_session?(env)
  end

  def test_skips_session_for_old_browser_with_xhr
    env = base_env.merge("HTTP_X_REQUESTED_WITH" => "XMLHttpRequest")

    refute @middleware.should_create_session?(env)
  end

  def test_skips_session_for_old_browser_with_unpoly
    env = base_env.merge("HTTP_X_UP_VERSION" => "3.0.0")

    refute @middleware.should_create_session?(env)
  end

  # === Integration: navigation detection gates session API call ===

  def test_navigation_request_triggers_session_creation
    session_created = false

    stub_session_creation(-> { session_created = true }) do
      env = build_navigation_env
      @middleware.call(env)
    end

    assert session_created, "Navigation request should trigger session creation"
  end

  def test_turbo_frame_request_skips_session_creation
    session_created = false

    stub_session_creation(-> { session_created = true }) do
      env = build_turbo_frame_env
      @middleware.call(env)
    end

    refute session_created, "Turbo Frame request should not trigger session creation"
  end

  def test_visitor_cookie_set_even_when_session_skipped
    _status, headers, _body = @middleware.call(build_turbo_frame_env)

    cookie_header = Array(headers["set-cookie"]).join("\n")
    assert_match(/_mbuzz_vid=/, cookie_header, "Visitor cookie should always be set")
  end

  def test_session_cookie_never_set
    _status, headers, _body = @middleware.call(build_navigation_env)

    cookie_header = Array(headers["set-cookie"]).join("\n")
    refute_match(/_mbuzz_sid=/, cookie_header, "Session cookie should never be set")
  end

  def test_env_keys_set_even_when_session_skipped
    captured_env = nil
    @app = ->(env) {
      captured_env = env
      [200, {}, ["OK"]]
    }
    @middleware = Mbuzz::Middleware::Tracking.new(@app)

    @middleware.call(build_turbo_frame_env)

    refute_nil captured_env["mbuzz.visitor_id"], "visitor_id should be set in env"
    refute_nil captured_env["mbuzz.session_id"], "session_id should be set in env"
  end

  private

  def base_env
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

  def build_navigation_env
    base_env.merge(
      "HTTP_SEC_FETCH_MODE" => "navigate",
      "HTTP_SEC_FETCH_DEST" => "document"
    )
  end

  def build_turbo_frame_env
    base_env.merge(
      "HTTP_SEC_FETCH_MODE" => "same-origin",
      "HTTP_SEC_FETCH_DEST" => "empty",
      "HTTP_TURBO_FRAME" => "content"
    )
  end

  def stub_session_creation(callback)
    Mbuzz::Client::SessionRequest.stub(:new, ->(**_params) {
      callback.call
      mock = Minitest::Mock.new
      mock.expect(:call, { success: true, visitor_id: "v", session_id: "s", channel: "direct" })
      mock
    }) do
      yield
      sleep 0.1
    end
  end
end
