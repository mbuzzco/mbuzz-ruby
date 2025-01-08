# frozen_string_literal: true

module Mbuzz
  class Client
    class ConversionRequest
      def initialize(event_id:, visitor_id:, user_id:, conversion_type:, revenue:, currency:, is_acquisition:, inherit_acquisition:, properties:, ip: nil, user_agent: nil, identifier: nil)
        @event_id = event_id
        @visitor_id = visitor_id
        @user_id = user_id
        @conversion_type = conversion_type
        @revenue = revenue
        @currency = currency
        @is_acquisition = is_acquisition
        @inherit_acquisition = inherit_acquisition
        @properties = properties
        @ip = ip
        @user_agent = user_agent
        @identifier = identifier
      end

      def call
        return false unless valid?

        { success: true, conversion_id: conversion_id, attribution: attribution }
      end

      private

      def valid?
        has_identifier? && present?(@conversion_type) && hash?(@properties) && conversion_id
      end

      def has_identifier?
        present?(@event_id) || present?(@visitor_id) || present?(@user_id)
      end

      def conversion_id
        @conversion_id ||= response&.dig("conversion", "id")
      end

      def attribution
        response&.dig("attribution")
      end

      def response
        @response ||= Api.post_with_response(CONVERSIONS_PATH, payload)
      end

      def payload
        { conversion: conversion_payload }
      end

      def conversion_payload
        base_payload
          .merge(optional_identifiers)
          .merge(optional_acquisition_fields)
          .merge(fingerprint_fields)
      end

      def base_payload
        {
          conversion_type: @conversion_type,
          currency: @currency,
          properties: @properties,
          timestamp: Time.now.utc.iso8601
        }
      end

      def optional_identifiers
        {}.tap do |h|
          h[:event_id] = @event_id if @event_id
          h[:visitor_id] = @visitor_id if @visitor_id
          h[:user_id] = @user_id if @user_id
          h[:revenue] = @revenue if @revenue
        end
      end

      def optional_acquisition_fields
        {}.tap do |h|
          h[:is_acquisition] = @is_acquisition if @is_acquisition
          h[:inherit_acquisition] = @inherit_acquisition if @inherit_acquisition
        end
      end

      def fingerprint_fields
        {}.tap do |h|
          h[:ip] = @ip if @ip
          h[:user_agent] = @user_agent if @user_agent
          h[:identifier] = @identifier if @identifier
        end
      end

      def present?(value) = value && !value.to_s.strip.empty?
      def hash?(value) = value.is_a?(Hash)
    end
  end
end
