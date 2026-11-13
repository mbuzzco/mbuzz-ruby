# frozen_string_literal: true

require "test_helper"

class Mbuzz::ConfigurationTest < Minitest::Test
  def setup
    @config = Mbuzz::Configuration.new
  end

  def test_validate_raises_when_api_key_is_nil
    error = assert_raises(Mbuzz::ConfigurationError) { @config.validate! }
    assert_match(/api_key is required/, error.message)
  end

  def test_validate_raises_when_api_key_is_empty_string
    @config.api_key = ""
    error = assert_raises(Mbuzz::ConfigurationError) { @config.validate! }
    assert_match(/api_key is required/, error.message)
  end

  def test_validate_passes_with_valid_api_key
    @config.api_key = "sk_test_123"
    assert_nil @config.validate!
  end

  def test_api_url_has_sensible_default
    assert_match(%r{mbuzz\.co/api}, @config.api_url)
  end

  AU_KEY = "sk_live_au_abc123"
  AU_URL = "https://ingest.example.com.au/api/v1"

  def test_resolve_api_url_honours_https_with_region_key_and_trims_slash
    assert_equal AU_URL, Mbuzz::Configuration.resolve_api_url(AU_KEY, "#{AU_URL}/")
  end

  def test_resolve_api_url_refuses_plain_http
    error = assert_raises(Mbuzz::ConfigurationError) do
      Mbuzz::Configuration.resolve_api_url(AU_KEY, "http://ingest.example.com.au")
    end
    assert_match(/https/, error.message)
  end

  def test_resolve_api_url_refuses_region_key_without_url
    assert_raises(Mbuzz::ConfigurationError) { Mbuzz::Configuration.resolve_api_url(AU_KEY, nil) }
  end

  def test_resolve_api_url_refuses_global_key_with_url
    assert_raises(Mbuzz::ConfigurationError) { Mbuzz::Configuration.resolve_api_url("sk_live_abc123", AU_URL) }
  end

  def test_resolve_api_url_lets_a_test_key_use_https_url
    assert_equal "https://staging.example.com/api/v1",
      Mbuzz::Configuration.resolve_api_url("sk_test_abc123", "https://staging.example.com/api/v1")
  end

  def test_init_refusal_does_not_half_apply
    Mbuzz.instance_variable_set(:@config, nil)
    Mbuzz.init(api_key: "sk_live_abc123")
    assert_raises(Mbuzz::ConfigurationError) { Mbuzz.init(api_key: AU_KEY) }
    assert_equal "sk_live_abc123", Mbuzz.config.api_key
  ensure
    Mbuzz.instance_variable_set(:@config, nil)
  end
end
