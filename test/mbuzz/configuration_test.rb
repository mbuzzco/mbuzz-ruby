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
end
