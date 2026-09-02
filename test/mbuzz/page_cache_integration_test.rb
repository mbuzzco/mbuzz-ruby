# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Attribution behind a full-page cache.
#
# A cached page is returned by the cache layer without ever entering the Rack
# stack, so the tracking middleware never runs: no visitor cookie is set, and
# every later event is rejected for having no one to attribute it to. The bug is
# silent — the page renders perfectly and nothing is logged.
#
# The fix is an endpoint the cache never stores. The browser calls it, and the
# SERVER mints the cookie on that response. The id is never created or read in
# JS, so it stays HttpOnly and keeps its full two-year life (a cookie written by
# document.cookie is capped at 7 days under Safari's ITP, and 24 hours after an
# ad click — a JS-owned id would be worse than the bug it fixes).
class Mbuzz::PageCacheIntegrationTest < Minitest::Test
  def setup
    @original_config = Mbuzz.instance_variable_get(:@config)
    Mbuzz.instance_variable_set(:@config, nil)

    Mbuzz.init(api_key: "sk_test_123")
  end

  def teardown
    Mbuzz.instance_variable_set(:@config, @original_config)
    Thread.current[:mbuzz_request] = nil
  end

  # --- The bug, reproduced ---

  # The cache serves the page itself; the Rack stack is never entered. This is
  # what every visitor to a cached page gets today.
  def test_cached_page_never_reaches_the_middleware_so_no_cookie_is_set
    reached = false
    cache = ->(_env) { [200, { "Content-Type" => "text/html" }, ["cached page"]] }
    app = Mbuzz::Middleware::Tracking.new(->(_env) { reached = true; [200, {}, ["origin"]] })

    _status, headers, _body = cache.call(build_env)

    refute reached, "the origin app should not be reached for a cached page"
    assert_nil headers["set-cookie"], "a cached response carries no visitor cookie"
    refute_nil app, "middleware exists but never runs — that is the whole bug"
  end

  # --- The fix ---

  def test_session_endpoint_mints_the_visitor_cookie
    _status, headers, _body = endpoint.call(build_env(path: Mbuzz::SESSION_ENDPOINT_PATH))

    assert_match(/_mbuzz_vid=/, cookie_header(headers))
  end

  def test_session_endpoint_keeps_the_cookie_httponly_and_long_lived
    _status, headers, _body = endpoint.call(build_env(path: Mbuzz::SESSION_ENDPOINT_PATH))
    cookie = cookie_header(headers)

    assert_match(/httponly/i, cookie, "the id must never be readable by JS")
    assert_match(/max-age=#{Mbuzz::VISITOR_COOKIE_MAX_AGE}/i, cookie)
  end

  # The endpoint is called by a script ON the page, so its own URL is useless.
  # The session must be recorded against the page the visitor is actually on.
  def test_session_endpoint_records_the_page_url_not_its_own
    captured = capture_session do
      endpoint.call(build_env(
        path: Mbuzz::SESSION_ENDPOINT_PATH,
        input: '{"url":"https://example.com/pricing","referrer":"https://google.com"}'
      ))
    end

    assert_equal "https://example.com/pricing", captured[:url]
    assert_equal "https://google.com", captured[:referrer]
  end

  # A returning visitor must keep their id, or every cached page view looks like
  # a new person and the journey is cut into fragments.
  def test_session_endpoint_preserves_an_existing_visitor_id
    env = build_env(path: Mbuzz::SESSION_ENDPOINT_PATH)
    env["HTTP_COOKIE"] = "_mbuzz_vid=returning456"

    captured = capture_session { endpoint.call(env) }

    assert_equal "returning456", captured[:visitor_id]
  end

  # Non-endpoint traffic must fall through untouched, or mounting the endpoint
  # would swallow the host application.
  def test_other_paths_fall_through_to_the_app
    status, _headers, body = endpoint.call(build_env(path: "/products"))

    assert_equal 200, status
    assert_equal ["OK"], body
  end

  # A GET would be cacheable by an intermediary, which is the bug all over
  # again. The endpoint only answers POST.
  def test_endpoint_ignores_a_get
    status, _headers, _body = endpoint.call(
      build_env(path: Mbuzz::SESSION_ENDPOINT_PATH, method: "GET")
    )

    assert_equal 200, status, "a GET falls through rather than minting"
  end

  def test_endpoint_response_is_not_cacheable
    _status, headers, _body = endpoint.call(build_env(path: Mbuzz::SESSION_ENDPOINT_PATH))

    assert_match(/no-store/, headers["cache-control"].to_s)
  end

  private

  def endpoint
    @endpoint ||= Mbuzz::Middleware::SessionEndpoint.new(->(_env) { [200, {}, ["OK"]] })
  end

  def cookie_header(headers)
    Array(headers["set-cookie"]).join("\n")
  end

  # Intercept the outbound session call rather than making one.
  def capture_session
    captured = nil
    Mbuzz::Client.stub(:session, ->(**kwargs) { captured = kwargs }) do
      yield
      sleep 0.05 # the middleware creates sessions on a background thread
    end
    captured
  end

  def build_env(path: "/products", method: "POST", input: "{}")
    {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "QUERY_STRING" => "",
      "HTTP_USER_AGENT" => "Mozilla/5.0",
      "rack.url_scheme" => "https",
      "HTTP_HOST" => "example.com",
      "SERVER_NAME" => "example.com",
      "SERVER_PORT" => "443",
      "REMOTE_ADDR" => "203.0.113.9",
      "rack.input" => StringIO.new(input)
    }
  end
end
