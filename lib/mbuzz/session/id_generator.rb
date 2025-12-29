# frozen_string_literal: true

require "digest"
require "securerandom"

module Mbuzz
  module Session
    class IdGenerator
      SESSION_TIMEOUT_SECONDS = 1800
      SESSION_ID_LENGTH = 64
      FINGERPRINT_LENGTH = 32

      class << self
        def generate_deterministic(visitor_id:, timestamp: Time.now.to_i)
          time_bucket = timestamp / SESSION_TIMEOUT_SECONDS
          raw = "#{visitor_id}_#{time_bucket}"
          Digest::SHA256.hexdigest(raw)[0, SESSION_ID_LENGTH]
        end

        def generate_from_fingerprint(client_ip:, user_agent:, timestamp: Time.now.to_i)
          fingerprint = Digest::SHA256.hexdigest("#{client_ip}|#{user_agent}")[0, FINGERPRINT_LENGTH]
          time_bucket = timestamp / SESSION_TIMEOUT_SECONDS
          raw = "#{fingerprint}_#{time_bucket}"
          Digest::SHA256.hexdigest(raw)[0, SESSION_ID_LENGTH]
        end

        def generate_random
          SecureRandom.hex(32)
        end
      end
    end
  end
end
