# frozen_string_literal: true

require "test_helper"
require "json"

class Mbuzz::ApiTest < Minitest::Test
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

  def test_post_returns_false_when_gem_is_disabled
    Mbuzz.config.enabled = false
    result = Mbuzz::Api.post("/events", { test: "data" })
    assert_equal false, result
  end

  def test_post_validates_api_key
    Mbuzz.config.api_key = nil
    result = Mbuzz::Api.post("/events", { test: "data" })
    assert_equal false, result
  end

  def test_post_returns_true_on_successful_2xx_response
    stub_http_success do
      result = Mbuzz::Api.post("/events", { test: "data" })
      assert_equal true, result
    end
  end

  def test_post_returns_false_on_4xx_response
    stub_http_error(400) do
      result = Mbuzz::Api.post("/events", { test: "data" })
      assert_equal false, result
    end
  end

  def test_post_returns_false_on_5xx_response
    stub_http_error(500) do
      result = Mbuzz::Api.post("/events", { test: "data" })
      assert_equal false, result
    end
  end

  def test_post_returns_false_on_network_error
    stub_http_timeout do
      result = Mbuzz::Api.post("/events", { test: "data" })
      assert_equal false, result
    end
  end

  # post_with_response tests
  def test_post_with_response_returns_nil_when_gem_is_disabled
    Mbuzz.config.enabled = false
    result = Mbuzz::Api.post_with_response("/events", { test: "data" })
    assert_nil result
  end

  def test_post_with_response_returns_parsed_json_on_success
    response_body = { "accepted" => 1, "events" => [{ "id" => "evt_abc123" }] }
    stub_http_success_with_body(response_body) do
      result = Mbuzz::Api.post_with_response("/events", { test: "data" })
      assert_equal response_body, result
    end
  end

  def test_post_with_response_returns_nil_on_4xx_response
    stub_http_error(400) do
      result = Mbuzz::Api.post_with_response("/events", { test: "data" })
      assert_nil result
    end
  end

  def test_post_with_response_returns_nil_on_5xx_response
    stub_http_error(500) do
      result = Mbuzz::Api.post_with_response("/events", { test: "data" })
      assert_nil result
    end
  end

  def test_post_with_response_returns_nil_on_network_error
    stub_http_timeout do
      result = Mbuzz::Api.post_with_response("/events", { test: "data" })
      assert_nil result
    end
  end

  def test_post_with_response_returns_nil_on_json_parse_error
    stub_http_success_with_invalid_json do
      result = Mbuzz::Api.post_with_response("/events", { test: "data" })
      assert_nil result
    end
  end

  private

  def stub_http_success
    Net::HTTP.stub(:new, MockHTTP.new(200)) do
      yield
    end
  end

  def stub_http_success_with_body(body)
    Net::HTTP.stub(:new, MockHTTP.new(200, JSON.generate(body))) do
      yield
    end
  end

  def stub_http_success_with_invalid_json
    Net::HTTP.stub(:new, MockHTTP.new(200, "not json")) do
      yield
    end
  end

  def stub_http_error(code)
    Net::HTTP.stub(:new, MockHTTP.new(code)) do
      yield
    end
  end

  def stub_http_timeout
    mock_http = Object.new
    def mock_http.use_ssl=(_); end
    def mock_http.verify_mode=(_); end
    def mock_http.cert_store=(_); end
    def mock_http.open_timeout=(_); end
    def mock_http.read_timeout=(_); end
    def mock_http.request(_)
      raise Net::ReadTimeout
    end

    Net::HTTP.stub(:new, mock_http) do
      yield
    end
  end

  class MockHTTP
    def initialize(response_code, body = "{}")
      @response_code = response_code
      @body = body
    end

    def use_ssl=(_); end
    def verify_mode=(_); end
    def cert_store=(_); end
    def open_timeout=(_); end
    def read_timeout=(_); end

    def request(_)
      MockResponse.new(@response_code, @body)
    end
  end

  class MockResponse
    attr_reader :code, :body

    def initialize(code, body = "{}")
      @code = code.to_s
      @body = body
    end
  end
end
