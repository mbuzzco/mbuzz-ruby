# frozen_string_literal: true

module Mbuzz
  class Client
    class TrackRequest
      def initialize(user_id, visitor_id, event_type, properties)
        @user_id = user_id
        @visitor_id = visitor_id
        @event_type = event_type
        @properties = properties
      end

      def call
        return false unless valid?

        { success: true, event_id: event["id"], event_type: event["event_type"],
          visitor_id: event["visitor_id"], session_id: event["session_id"] }
      end

      private

      def valid?
        present?(@event_type) && hash?(@properties) && (@user_id || @visitor_id) && event
      end

      def event
        @event ||= response&.dig("events", 0)
      end

      def response
        @response ||= Api.post_with_response(EVENTS_PATH, { events: [payload] })
      end

      def payload
        { user_id: @user_id, visitor_id: @visitor_id, event_type: @event_type,
          properties: @properties, timestamp: Time.now.utc.iso8601 }.compact
      end

      def present?(value) = value && !value.to_s.strip.empty?
      def hash?(value) = value.is_a?(Hash)
    end
  end
end
