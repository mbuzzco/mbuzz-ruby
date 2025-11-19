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

    cookie_header = headers["set-cookie"]
    refute_nil cookie_header
    assert_match(/mbuzz_visitor_id=/, cookie_header)
  end

  def test_preserves_existing_visitor_id
    @existing_visitor_id = "existing123"
    _status, headers, _body = call_result

    cookie_header = headers["set-cookie"]
    assert_match(/mbuzz_visitor_id=existing123/, cookie_header)
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

    if @existing_visitor_id
      env["HTTP_COOKIE"] = "mbuzz_visitor_id=#{@existing_visitor_id}"
    end

    env
  end
end
