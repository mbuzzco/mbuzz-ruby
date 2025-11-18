# frozen_string_literal: true

require "test_helper"

class Mbuzz::ControllerHelpersTest < Minitest::Test
  def setup
    @original_config = Mbuzz.instance_variable_get(:@config)
    Mbuzz.instance_variable_set(:@config, nil)

    Mbuzz.configure do |config|
      config.api_key = "sk_test_123"
      config.api_url = "https://mbuzz.co/api/v1"
    end

    @controller = TestController.new
  end

  def teardown
    Mbuzz.instance_variable_set(:@config, @original_config)
  end

  def test_mbuzz_track_calls_client_track_with_user_id
    stub_client_track do
      result = @controller.mbuzz_track("Purchase", properties: { amount: 99 })
      assert_equal true, result
      assert @track_called
    end
  end

  def test_mbuzz_track_calls_client_track_with_visitor_id
    @controller.set_visitor_id("visitor123")
    stub_client_track do
      result = @controller.mbuzz_track("Page View")
      assert_equal true, result
      assert @track_called
    end
  end

  def test_mbuzz_identify_calls_client_identify
    stub_client_identify do
      result = @controller.mbuzz_identify(traits: { email: "test@example.com" })
      assert_equal true, result
      assert @identify_called
    end
  end

  def test_mbuzz_alias_calls_client_alias
    @controller.set_visitor_id("visitor456")
    stub_client_alias do
      result = @controller.mbuzz_alias
      assert_equal true, result
      assert @alias_called
    end
  end

  def test_mbuzz_user_id_returns_user_id_from_env
    @controller.set_user_id(789)
    assert_equal 789, @controller.mbuzz_user_id
  end

  def test_mbuzz_visitor_id_returns_visitor_id_from_env
    @controller.set_visitor_id("visitor789")
    assert_equal "visitor789", @controller.mbuzz_visitor_id
  end

  private

  def stub_client_track
    @track_called = false
    Mbuzz::Client.stub(:track, ->(*args) { @track_called = true; true }) do
      yield
    end
  end

  def stub_client_identify
    @identify_called = false
    Mbuzz::Client.stub(:identify, ->(*args) { @identify_called = true; true }) do
      yield
    end
  end

  def stub_client_alias
    @alias_called = false
    Mbuzz::Client.stub(:alias, ->(*args) { @alias_called = true; true }) do
      yield
    end
  end

  # Mock controller for testing
  class TestController
    include Mbuzz::ControllerHelpers

    attr_accessor :request

    def initialize
      @request = MockRequest.new
    end

    def set_user_id(user_id)
      @request.env[Mbuzz::ENV_USER_ID_KEY] = user_id
    end

    def set_visitor_id(visitor_id)
      @request.env[Mbuzz::ENV_VISITOR_ID_KEY] = visitor_id
    end
  end

  class MockRequest
    attr_reader :env

    def initialize
      @env = {}
    end
  end
end
