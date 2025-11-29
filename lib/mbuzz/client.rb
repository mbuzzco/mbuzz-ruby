# frozen_string_literal: true

require_relative "client/track_request"
require_relative "client/identify_request"
require_relative "client/conversion_request"
require_relative "client/session_request"

module Mbuzz
  class Client
    def self.track(user_id: nil, visitor_id: nil, session_id: nil, event_type:, properties: {})
      TrackRequest.new(user_id, visitor_id, session_id, event_type, properties).call
    end

    def self.identify(user_id:, visitor_id: nil, traits: {})
      IdentifyRequest.new(user_id, visitor_id, traits).call
    end

    def self.conversion(event_id: nil, visitor_id: nil, conversion_type:, revenue: nil, currency: "USD", properties: {})
      ConversionRequest.new(event_id, visitor_id, conversion_type, revenue, currency, properties).call
    end

    def self.session(visitor_id:, session_id:, url:, referrer: nil, started_at: nil)
      SessionRequest.new(visitor_id, session_id, url, referrer, started_at).call
    end
  end
end
