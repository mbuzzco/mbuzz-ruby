# frozen_string_literal: true

module Mbuzz
  class Client
    class AliasRequest
      def initialize(user_id, visitor_id)
        @user_id = user_id
        @visitor_id = visitor_id
      end

      def call
        return false unless valid?

        Api.post(ALIAS_PATH, payload)
      end

      private

      def valid?
        id?(@user_id) && string?(@visitor_id)
      end

      def payload
        { user_id: @user_id, visitor_id: @visitor_id, timestamp: Time.now.utc.iso8601 }
      end

      def id?(value) = value.is_a?(String) || value.is_a?(Numeric)
      def string?(value) = value.is_a?(String) && !value.strip.empty?
    end
  end
end
