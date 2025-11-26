# frozen_string_literal: true

module Mbuzz
  class Client
    class IdentifyRequest
      def initialize(user_id, traits)
        @user_id = user_id
        @traits = traits
      end

      def call
        return false unless valid?

        Api.post(IDENTIFY_PATH, payload)
      end

      private

      def valid?
        id?(@user_id) && hash?(@traits)
      end

      def payload
        { user_id: @user_id, traits: @traits, timestamp: Time.now.utc.iso8601 }
      end

      def id?(value) = value.is_a?(String) || value.is_a?(Numeric)
      def hash?(value) = value.is_a?(Hash)
    end
  end
end
