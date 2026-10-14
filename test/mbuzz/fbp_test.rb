# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Meta merges a server event with the browser Pixel's event for the same action
# on event_name + fbp when the event IDs differ. The SDK reads the cookie the
# Pixel already set and forwards it verbatim: never set, changed or invented.
#
# End to end: sdk_integration_tests/scenarios/fbp_capture_test.rb.
class Mbuzz::FbpTest < Minitest::Test
  FBP = "fb.1.1758585600000.1234567890"
  VISITOR = "a1b2c3d4" * 8

  def setup
    @original_config = Mbuzz.instance_variable_get(:@config)
    Mbuzz.instance_variable_set(:@config, nil)
    Mbuzz.init(api_key: "sk_test_123")
  end

  def teardown
    Mbuzz.instance_variable_set(:@config, @original_config)
    Thread.current[:mbuzz_request] = nil
  end

  # --- the cookie ---

  def test_reads_a_well_formed_value
    assert_equal FBP, Mbuzz::Fbp.read(FBP)
  end

  def test_reads_a_value_with_metas_appendix
    assert_equal "#{FBP}.AQECAQIB", Mbuzz::Fbp.read("#{FBP}.AQECAQIB")
  end

  def test_absent_is_nil
    assert_nil Mbuzz::Fbp.read(nil)
    assert_nil Mbuzz::Fbp.read("")
  end

  def test_drops_a_malformed_value
    [
      "not-a-meta-cookie", "#{FBP}.", "#{FBP}.a b", "#{FBP}.AQEC.AQEC",
      "#{FBP}.AQEC\n", "fb.1.1758585600000.abc.AQEC", "xx.1.1758585600000.1234567890.AQEC"
    ].each do |value|
      assert_nil Mbuzz::Fbp.read(value), "#{value.inspect} is not Meta's format"
    end
  end

  # --- the session request ---

  def test_session_request_carries_fbp
    payload = nil
    Mbuzz::Api.stub(:post_with_response, ->(_path, body) { payload = body; nil }) do
      Mbuzz::Client.session(visitor_id: VISITOR, session_id: "s1", url: "https://shop.test/", fbp: FBP)
    end

    assert_equal FBP, payload[:session][:fbp]
  end

  def test_session_request_omits_the_key_when_absent
    payload = nil
    Mbuzz::Api.stub(:post_with_response, ->(_path, body) { payload = body; nil }) do
      Mbuzz::Client.session(visitor_id: VISITOR, session_id: "s1", url: "https://shop.test/")
    end

    refute payload[:session].key?(:fbp), "omitted, not null"
  end

  # --- both session paths ---

  def test_the_page_path_forwards_fbp
    captured = capture_session do
      Mbuzz::Middleware::Tracking.new(ok_app).call(page_env(cookie: "_mbuzz_vid=#{VISITOR}; _fbp=#{FBP}.AQECAQIB"))
    end

    assert_equal "#{FBP}.AQECAQIB", captured[:fbp]
  end

  def test_the_page_path_sends_nothing_without_the_cookie
    captured = capture_session do
      Mbuzz::Middleware::Tracking.new(ok_app).call(page_env(cookie: "_mbuzz_vid=#{VISITOR}"))
    end

    assert_nil captured[:fbp]
  end

  def test_the_endpoint_path_forwards_fbp
    captured = capture_session do
      Mbuzz::Middleware::SessionEndpoint.new(ok_app).call(
        page_env(path: Mbuzz::SESSION_ENDPOINT_PATH, method: "POST", cookie: "_fbp=#{FBP}",
                 input: { url: "https://shop.test/" }.to_json)
      )
    end

    assert_equal FBP, captured[:fbp]
  end

  def test_the_endpoint_path_drops_a_malformed_fbp
    captured = capture_session do
      Mbuzz::Middleware::SessionEndpoint.new(ok_app).call(
        page_env(path: Mbuzz::SESSION_ENDPOINT_PATH, method: "POST", cookie: "_fbp=#{FBP}.a b",
                 input: { url: "https://shop.test/" }.to_json)
      )
    end

    assert_nil captured[:fbp]
  end

  private

  def ok_app = ->(_env) { [200, {}, ["OK"]] }

  def capture_session
    captured = nil
    Mbuzz::Client.stub(:session, ->(**kwargs) { captured = kwargs }) do
      yield
      sleep 0.05 # sessions are created on a background thread
    end
    captured
  end

  def page_env(path: "/", method: "GET", cookie: nil, input: "")
    env = {
      "REQUEST_METHOD" => method, "PATH_INFO" => path, "QUERY_STRING" => "",
      "HTTP_USER_AGENT" => "Mozilla/5.0", "HTTP_SEC_FETCH_MODE" => "navigate",
      "HTTP_SEC_FETCH_DEST" => "document", "rack.url_scheme" => "https",
      "HTTP_HOST" => "example.com", "SERVER_NAME" => "example.com", "SERVER_PORT" => "443",
      "REMOTE_ADDR" => "203.0.113.9", "rack.input" => StringIO.new(input)
    }
    env["HTTP_COOKIE"] = cookie if cookie
    env
  end
end
