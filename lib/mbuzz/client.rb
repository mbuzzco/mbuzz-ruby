# frozen_string_literal: true

require_relative "client/track_request"
require_relative "client/identify_request"
require_relative "client/alias_request"
require_relative "client/conversion_request"

module Mbuzz
  class Client
    def self.track(user_id: nil, visitor_id: nil, event_type:, properties: {})
      TrackRequest.new(user_id, visitor_id, event_type, properties).call
    end

    def self.identify(user_id:, traits: {})
      IdentifyRequest.new(user_id, traits).call
    end

    def self.alias(user_id:, visitor_id:)
      AliasRequest.new(user_id, visitor_id).call
    end

    def self.conversion(event_id: nil, visitor_id: nil, conversion_type:, revenue: nil, currency: "USD", properties: {})
      ConversionRequest.new(event_id, visitor_id, conversion_type, revenue, currency, properties).call
    end
  end
end
