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

  # Validation tests - ensuring invalid input doesn't crash the app
  def test_track_returns_false_with_nil_event_type
    @event_type = nil
    assert_equal false, track_result
  end

  def test_track_returns_false_with_empty_event_type
    @event_type = ""
    assert_equal false, track_result
  end

  def test_track_returns_false_with_whitespace_event_type
    @event_type = "   "
    assert_equal false, track_result
  end

  def test_track_returns_false_with_invalid_properties
    @properties = "not a hash"
    assert_equal false, track_result
  end

  def test_track_returns_false_without_user_or_visitor_id
    @user_id = nil
    @visitor_id = nil
    assert_equal false, track_result
  end

  def test_identify_returns_false_with_nil_user_id
    @user_id = nil
    assert_equal false, identify_result
  end

  def test_identify_returns_false_with_invalid_traits
    @traits = "not a hash"
    assert_equal false, identify_result
  end

  def test_alias_returns_false_with_nil_user_id
    @user_id = nil
    assert_equal false, alias_result
  end

  def test_alias_returns_false_with_nil_visitor_id
    @visitor_id = nil
    assert_equal false, alias_result
  end

  def test_alias_returns_false_with_empty_visitor_id
    @visitor_id = ""
    assert_equal false, alias_result
  end

  def test_alias_returns_false_with_invalid_visitor_id_type
    @visitor_id = 456
    assert_equal false, alias_result
  end

  private

  def track_result
    Mbuzz::Client.track(
      user_id: defined?(@user_id) ? @user_id : 123,
      visitor_id: @visitor_id,
      event_type: defined?(@event_type) ? @event_type : "Signup",
      properties: @properties || {}
    )
  end

  def identify_result
    Mbuzz::Client.identify(
      user_id: defined?(@user_id) ? @user_id : 123,
      traits: @traits || {}
    )
  end

  def alias_result
    Mbuzz::Client.alias(
      user_id: defined?(@user_id) ? @user_id : 123,
      visitor_id: defined?(@visitor_id) ? @visitor_id : "visitor123"
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
