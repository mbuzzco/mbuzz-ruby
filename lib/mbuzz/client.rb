# frozen_string_literal: true

module Mbuzz
  class Client
    def self.track(user_id: nil, visitor_id: nil, event:, properties: {})
      Api.post(EVENTS_PATH, {
        user_id: user_id,
        visitor_id: visitor_id,
        event: event,
        properties: properties,
        timestamp: Time.now.to_i
      }.compact)
    end

    def self.identify(user_id:, traits: {})
      Api.post(IDENTIFY_PATH, {
        user_id: user_id,
        traits: traits,
        timestamp: Time.now.to_i
      })
    end

    def self.alias(user_id:, visitor_id:)
      Api.post(ALIAS_PATH, {
        user_id: user_id,
        visitor_id: visitor_id,
        timestamp: Time.now.to_i
      })
    end
  end
end
