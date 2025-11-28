# frozen_string_literal: true

module Mbuzz
  class Client
    class SessionRequest
      def initialize(visitor_id, session_id, url, referrer, started_at)
        @visitor_id = visitor_id
        @session_id = session_id
        @url = url
        @referrer = referrer
        @started_at = started_at || Time.now.utc.iso8601
      end

      def call
        return false unless valid?

        Api.post(SESSIONS_PATH, payload)
      end

      private

      attr_reader :visitor_id, :session_id, :url, :referrer, :started_at

      def valid?
        present?(visitor_id) && present?(session_id) && present?(url)
      end

      def payload
        {
          session: {
            visitor_id: visitor_id,
            session_id: session_id,
            url: url,
            referrer: referrer,
            started_at: started_at
          }.compact
        }
      end

      def present?(value) = value && !value.to_s.strip.empty?
    end
  end
end
