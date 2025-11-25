# frozen_string_literal: true

module Mbuzz
  class Client
    def self.track(user_id: nil, visitor_id: nil, event_type:, properties: {})
      return false unless valid_event_type?(event_type)
      return false unless valid_properties?(properties)
      return false unless valid_identifier?(user_id, visitor_id)

      event = {
        user_id: user_id,
        visitor_id: visitor_id,
        event_type: event_type,
        properties: properties,
        timestamp: Time.now.utc.iso8601
      }.compact

      Api.post(EVENTS_PATH, { events: [event] })
    end

    def self.identify(user_id:, traits: {})
      return false unless valid_user_id?(user_id)
      return false unless valid_traits?(traits)

      Api.post(IDENTIFY_PATH, {
        user_id: user_id,
        traits: traits,
        timestamp: Time.now.utc.iso8601
      })
    end

    def self.alias(user_id:, visitor_id:)
      return false unless valid_user_id?(user_id)
      return false unless valid_visitor_id?(visitor_id)

      Api.post(ALIAS_PATH, {
        user_id: user_id,
        visitor_id: visitor_id,
        timestamp: Time.now.utc.iso8601
      })
    end

    private_class_method def self.valid_event_type?(event_type)
      return false if event_type.nil?
      return false if event_type.to_s.strip.empty?
      true
    end

    private_class_method def self.valid_properties?(properties)
      properties.is_a?(Hash)
    end

    private_class_method def self.valid_traits?(traits)
      traits.is_a?(Hash)
    end

    private_class_method def self.valid_user_id?(user_id)
      return false if user_id.nil?
      user_id.is_a?(String) || user_id.is_a?(Numeric)
    end

    private_class_method def self.valid_visitor_id?(visitor_id)
      return false if visitor_id.nil?
      return false unless visitor_id.is_a?(String)
      return false if visitor_id.strip.empty?
      true
    end

    private_class_method def self.valid_identifier?(user_id, visitor_id)
      user_id || visitor_id
    end
  end
end
