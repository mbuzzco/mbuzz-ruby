# frozen_string_literal: true

require "test_helper"

class Mbuzz::ClientTest < Minitest::Test
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

  # Track tests
  def test_track_returns_true_on_success
    stub_api_success do
      assert_equal true, track_result
    end
  end

  def test_track_returns_false_on_failure
    stub_api_failure do
      assert_equal false, track_result
    end
  end

  def test_track_works_with_user_id
    @user_id = 123
    @visitor_id = nil
    stub_api_success do
      assert_equal true, track_result
    end
  end

  def test_track_works_with_visitor_id
    @user_id = nil
    @visitor_id = "visitor123"
    stub_api_success do
      assert_equal true, track_result
    end
  end

  # Identify tests
  def test_identify_returns_true_on_success
    stub_api_success do
      assert_equal true, identify_result
    end
  end

  def test_identify_returns_false_on_failure
    stub_api_failure do
      assert_equal false, identify_result
    end
  end

  # Alias tests
  def test_alias_returns_true_on_success
    stub_api_success do
      assert_equal true, alias_result
    end
  end

  def test_alias_returns_false_on_failure
    stub_api_failure do
      assert_equal false, alias_result
    end
  end

  private

  def track_result
    @track_result ||= Mbuzz::Client.track(
      user_id: @user_id || 123,
      visitor_id: @visitor_id,
      event: @event || "Signup",
      properties: @properties
    )
  end

  def identify_result
    @identify_result ||= Mbuzz::Client.identify(
      user_id: @user_id || 123,
      traits: @traits || {}
    )
  end

  def alias_result
    @alias_result ||= Mbuzz::Client.alias(
      user_id: @user_id || 123,
      visitor_id: @visitor_id || "visitor123"
    )
  end

  def stub_api_success
    Mbuzz::Api.stub(:post, true) do
      yield
    end
  end

  def stub_api_failure
    Mbuzz::Api.stub(:post, false) do
      yield
    end
  end
end
