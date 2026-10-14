# frozen_string_literal: true

# Time#iso8601 lives here, not in core. Rack and Rails load it; a plain script
# did not, and the session call then failed silently (rescued to false).
require "time"

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

      def initialize(visitor_id:, session_id:, url:, referrer: nil, device_fingerprint: nil,
                     user_agent: nil, started_at: nil, ip: nil, fbp: nil)
        @visitor_id = visitor_id
        @session_id = session_id
        @url = url
        @referrer = referrer
        @device_fingerprint = device_fingerprint
        @user_agent = user_agent
        @started_at = started_at
        @ip = ip
        @fbp = fbp
      end

      def call
        return false unless valid?

        parse_response(response)
      rescue StandardError
        false
      end

      private

      attr_reader :visitor_id, :session_id, :url, :referrer, :device_fingerprint, :user_agent,
        :started_at, :ip, :fbp

      def valid?
        present?(visitor_id) && present?(session_id) && present?(url)
      end

      def response
        @response ||= Api.post_with_response(SESSIONS_PATH, { session: payload })
      end

      # `ip` is the visitor's address, which the middleware already extracted to
      # compute `device_fingerprint` (SHA256(ip|user_agent)). It was computed
      # and then dropped here until 2026-09-17: mbuzz needs it for Meta's
      # `client_ip_address`, which Meta documents as required for website
      # events, and the events/conversions payloads have always carried it.
      def payload
        {
          visitor_id: visitor_id,
          session_id: session_id,
          url: url,
          referrer: referrer,
          device_fingerprint: device_fingerprint,
          user_agent: user_agent,
          ip: ip,
          # Meta's browser id, already format-checked by Mbuzz::Fbp. Dropped by
          # .compact when absent: omitted, not null.
          fbp: fbp,
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
