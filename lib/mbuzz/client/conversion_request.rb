# frozen_string_literal: true

module Mbuzz
  class Client
    class ConversionRequest
      def initialize(visitor_id, conversion_type, revenue, currency, properties, event_id)
        @visitor_id = visitor_id
        @conversion_type = conversion_type
        @revenue = revenue
        @currency = currency
        @properties = properties
        @event_id = event_id
      end

      def call
        return false unless valid?

        { success: true, conversion_id: conversion_id, attribution: attribution }
      end

      private

      def valid?
        string?(@visitor_id) && present?(@conversion_type) && hash?(@properties) && conversion_id
      end

      def conversion_id
        @conversion_id ||= response&.dig("id")
      end

      def attribution
        response&.dig("attribution")
      end

      def response
        @response ||= Api.post_with_response(CONVERSIONS_PATH, payload)
      end

      def payload
        base_payload
          .tap { |p| p[:revenue] = @revenue if @revenue }
          .tap { |p| p[:event_id] = @event_id if @event_id }
      end

      def base_payload
        { visitor_id: @visitor_id, conversion_type: @conversion_type, currency: @currency,
          properties: @properties, timestamp: Time.now.utc.iso8601 }
      end

      def present?(value) = value && !value.to_s.strip.empty?
      def string?(value) = value.is_a?(String) && !value.strip.empty?
      def hash?(value) = value.is_a?(Hash)
    end
  end
end
