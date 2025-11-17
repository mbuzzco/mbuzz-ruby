# frozen_string_literal: true

require "test_helper"

class Mbuzz::RequestContextTest < Minitest::Test
  def setup
    @request = MockRequest.new(
      url: "https://example.com/page?utm_source=google",
      referrer: "https://google.com",
      user_agent: "Mozilla/5.0"
    )
  end

  def teardown
    # Clean up thread-local storage
    Thread.current[:mbuzz_request] = nil
  end

  def test_with_context_stores_request_in_thread_local
    Mbuzz::RequestContext.with_context(request: @request) do
      assert_equal @request, Thread.current[:mbuzz_request]
    end
  end

  def test_with_context_cleans_up_after_block
    Mbuzz::RequestContext.with_context(request: @request) do
      # Inside block
    end
    assert_nil Thread.current[:mbuzz_request]
  end

  def test_with_context_cleans_up_even_on_exception
    assert_raises(RuntimeError) do
      Mbuzz::RequestContext.with_context(request: @request) do
        raise "Something went wrong"
      end
    end
    assert_nil Thread.current[:mbuzz_request]
  end

  def test_current_returns_nil_when_no_context
    assert_nil Mbuzz::RequestContext.current
  end

  def test_current_returns_context_when_inside_with_context
    Mbuzz::RequestContext.with_context(request: @request) do
      context = Mbuzz::RequestContext.current
      refute_nil context
      assert_instance_of Mbuzz::RequestContext, context
    end
  end

  def test_url_returns_request_url
    Mbuzz::RequestContext.with_context(request: @request) do
      context = Mbuzz::RequestContext.current
      assert_equal "https://example.com/page?utm_source=google", context.url
    end
  end

  def test_referrer_returns_request_referrer
    Mbuzz::RequestContext.with_context(request: @request) do
      context = Mbuzz::RequestContext.current
      assert_equal "https://google.com", context.referrer
    end
  end

  def test_user_agent_returns_request_user_agent
    Mbuzz::RequestContext.with_context(request: @request) do
      context = Mbuzz::RequestContext.current
      assert_equal "Mozilla/5.0", context.user_agent
    end
  end

  # Mock request object for testing
  class MockRequest
    attr_reader :url, :referrer, :user_agent

    def initialize(url:, referrer:, user_agent:)
      @url = url
      @referrer = referrer
      @user_agent = user_agent
    end
  end
end
