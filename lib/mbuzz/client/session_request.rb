# frozen_string_literal: true

module Mbuzz
  class Client
    class SessionRequest
      # Response keys
      STATUS_KEY = "status"
      VISITOR_ID_KEY = "visitor_id"
      SESSION_ID_KEY = "session_id"
      CHANNEL_KEY = "channel"

      # Response values
      ACCEPTED_STATUS = "accepted"

      def initialize(visitor_id:, session_id:, url:, referrer: nil, device_fingerprint: nil, started_at: nil)
        @visitor_id = visitor_id
        @session_id = session_id
        @url = url
        @referrer = referrer
        @device_fingerprint = device_fingerprint
        @started_at = started_at
      end

      def call
        return false unless valid?

        parse_response(response)
      rescue StandardError
        false
      end

      private

      attr_reader :visitor_id, :session_id, :url, :referrer, :device_fingerprint, :started_at

      def valid?
        present?(visitor_id) && present?(session_id) && present?(url)
      end

      def response
        @response ||= Api.post_with_response(SESSIONS_PATH, { session: payload })
      end

      def payload
        {
          visitor_id: visitor_id,
          session_id: session_id,
          url: url,
          referrer: referrer,
          device_fingerprint: device_fingerprint,
          started_at: started_at || Time.now.utc.iso8601
        }.compact
      end

      def parse_response(resp)
        return false unless accepted?(resp)

        {
          success: true,
          visitor_id: resp[VISITOR_ID_KEY],
          session_id: resp[SESSION_ID_KEY],
          channel: resp[CHANNEL_KEY]
        }
      end

      def accepted?(resp)
        resp && resp[STATUS_KEY] == ACCEPTED_STATUS
      end

      def present?(value)
        value && !value.to_s.strip.empty?
      end
    end
  end
end
