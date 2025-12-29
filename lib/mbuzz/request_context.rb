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

    def ip
      @request.env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip ||
        @request.env["HTTP_X_REAL_IP"] ||
        @request.ip
    end

    def enriched_properties(custom = {})
      { url: url, referrer: referrer }.compact.merge(custom)
    end
  end
end
