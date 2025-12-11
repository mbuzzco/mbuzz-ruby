# frozen_string_literal: true

require_relative "mbuzz/version"
require_relative "mbuzz/configuration"
require_relative "mbuzz/visitor/identifier"
require_relative "mbuzz/request_context"
require_relative "mbuzz/api"
require_relative "mbuzz/client"
require_relative "mbuzz/middleware/tracking"
require_relative "mbuzz/controller_helpers"

require_relative "mbuzz/railtie" if defined?(Rails::Railtie)

module Mbuzz
  class Error < StandardError; end

  EVENTS_PATH = "/events"
  IDENTIFY_PATH = "/identify"
  CONVERSIONS_PATH = "/conversions"
  SESSIONS_PATH = "/sessions"

  VISITOR_COOKIE_NAME = "_mbuzz_vid"
  VISITOR_COOKIE_MAX_AGE = 60 * 60 * 24 * 365 * 2 # 2 years
  VISITOR_COOKIE_PATH = "/"
  VISITOR_COOKIE_SAME_SITE = "Lax"

  SESSION_COOKIE_NAME = "_mbuzz_sid"
  SESSION_COOKIE_MAX_AGE = 30 * 60 # 30 minutes

  SESSION_USER_ID_KEY = "user_id"
  ENV_USER_ID_KEY = "mbuzz.user_id"
  ENV_VISITOR_ID_KEY = "mbuzz.visitor_id"
  ENV_SESSION_ID_KEY = "mbuzz.session_id"

  # ============================================================================
  # Configuration
  # ============================================================================

  def self.config
    @config ||= Configuration.new
  end

  # New simplified configuration method (v0.5.0)
  # @param api_key [String] Your mbuzz API key
  # @param api_url [String, nil] Override API URL (defaults to https://mbuzz.co/api/v1)
  # @param session_timeout [Integer, nil] Session timeout in seconds
  # @param debug [Boolean, nil] Enable debug logging
  # @param skip_paths [Array<String>, nil] Additional paths to skip tracking (e.g., ["/admin", "/internal"])
  # @param skip_extensions [Array<String>, nil] Additional extensions to skip (e.g., [".pdf"])
  def self.init(api_key:, api_url: nil, session_timeout: nil, debug: nil, skip_paths: nil, skip_extensions: nil)
    config.api_key = api_key
    config.api_url = api_url if api_url
    config.session_timeout = session_timeout if session_timeout
    config.debug = debug unless debug.nil?
    config.skip_paths = skip_paths if skip_paths
    config.skip_extensions = skip_extensions if skip_extensions
    config
  end

  # @deprecated Use {.init} instead
  def self.configure
    warn "[DEPRECATION] Mbuzz.configure is deprecated. Use Mbuzz.init(api_key: ...) instead."
    yield(config)
  end

  # ============================================================================
  # Context Accessors
  # ============================================================================

  def self.visitor_id
    RequestContext.current&.request&.env&.dig(ENV_VISITOR_ID_KEY) || fallback_visitor_id
  end

  def self.fallback_visitor_id
    @fallback_visitor_id ||= Visitor::Identifier.generate
  end
  private_class_method :fallback_visitor_id

  def self.user_id
    RequestContext.current&.request&.env&.dig(ENV_USER_ID_KEY)
  end

  def self.session_id
    RequestContext.current&.request&.env&.dig(ENV_SESSION_ID_KEY)
  end

  # ============================================================================
  # 4-Call Model API
  # ============================================================================

  # Track an event (journey step)
  #
  # @param event_type [String] The name of the event
  # @param properties [Hash] Custom event properties (url, referrer auto-added)
  # @return [Hash, false] Result hash on success, false on failure
  #
  # @example
  #   Mbuzz.event("add_to_cart", product_id: "SKU-123", price: 49.99)
  #
  def self.event(event_type, **properties)
    Client.track(
      visitor_id: visitor_id,
      session_id: session_id,
      user_id: user_id,
      event_type: event_type,
      properties: enriched_properties(properties)
    )
  end

  # @deprecated Use {.event} instead
  def self.track(event_type, properties: {})
    warn "[DEPRECATION] Mbuzz.track is deprecated. Use Mbuzz.event(event_type, **properties) instead."
    event(event_type, **properties)
  end

  # Track a conversion (revenue-generating outcome)
  #
  # @param conversion_type [String] The type of conversion
  # @param revenue [Numeric, nil] Revenue amount
  # @param user_id [String, nil] User ID for acquisition-linked conversions
  # @param is_acquisition [Boolean] Mark this as the acquisition conversion for this user
  # @param inherit_acquisition [Boolean] Inherit attribution from user's acquisition conversion
  # @param properties [Hash] Custom properties
  # @return [Hash, false] Result hash on success, false on failure
  #
  # @example Basic conversion
  #   Mbuzz.conversion("purchase", revenue: 99.99, order_id: "ORD-123")
  #
  # @example Acquisition conversion (marks signup as THE acquisition moment)
  #   Mbuzz.conversion("signup", user_id: "user_123", is_acquisition: true)
  #
  # @example Recurring revenue (inherits attribution from acquisition)
  #   Mbuzz.conversion("payment", user_id: "user_123", revenue: 49.00, inherit_acquisition: true)
  #
  def self.conversion(conversion_type, revenue: nil, user_id: nil, is_acquisition: false, inherit_acquisition: false, **properties)
    Client.conversion(
      visitor_id: visitor_id,
      user_id: user_id,
      conversion_type: conversion_type,
      revenue: revenue,
      is_acquisition: is_acquisition,
      inherit_acquisition: inherit_acquisition,
      properties: enriched_properties(properties)
    )
  end

  # Identify a user and optionally link to current visitor
  #
  # @param user_id [String, Numeric] Your application's user identifier
  # @param traits [Hash] User attributes (email, name, plan, etc.)
  # @param visitor_id [String, nil] Explicit visitor ID (auto-captured from cookie if nil)
  # @return [Hash, false] Result hash with identity_id and visitor_linked, or false on failure
  #
  # @example Basic identification
  #   Mbuzz.identify("user_123", traits: { email: "jane@example.com" })
  #
  # @example With explicit visitor_id
  #   Mbuzz.identify("user_123", visitor_id: "abc123...", traits: { email: "jane@example.com" })
  #
  def self.identify(user_id, traits: {}, visitor_id: nil)
    Client.identify(
      user_id: user_id,
      visitor_id: visitor_id || self.visitor_id,
      traits: traits
    )
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  def self.enriched_properties(custom_properties)
    return custom_properties unless RequestContext.current

    RequestContext.current.enriched_properties(custom_properties)
  end
  private_class_method :enriched_properties
end
