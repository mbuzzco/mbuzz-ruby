# frozen_string_literal: true

module Mbuzz
  class RequestContext
    def self.with_context(request:)
      Thread.current[:mbuzz_request] = request
      yield
    ensure
      Thread.current[:mbuzz_request] = nil
    end

    def self.current
      return nil unless Thread.current[:mbuzz_request]

      new(Thread.current[:mbuzz_request])
    end

    attr_reader :request

    def initialize(request)
      @request = request
    end

    def url
      @request.url
    end

    def referrer
      @request.referrer
    end

    def user_agent
      @request.user_agent
    end
  end
end
