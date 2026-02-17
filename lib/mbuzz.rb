# frozen_string_literal: true

require_relative "mbuzz/version"
require_relative "mbuzz/configuration"
require_relative "mbuzz/visitor/identifier"
require_relative "mbuzz/request_context"
require_relative "mbuzz/api"
require_relative "mbuzz/client"
require_relative "mbuzz/middleware/tracking"
require_relative "mbuzz/controller_helpers"

# CurrentAttributes for automatic background job context propagation (Rails only)
require_relative "mbuzz/current" if defined?(ActiveSupport::CurrentAttributes)

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

  # Returns visitor_id from Current (background jobs) or request context
  def self.visitor_id
    current_visitor_id || RequestContext.current&.request&.env&.dig(ENV_VISITOR_ID_KEY)
  end

  def self.user_id
    current_user_id || RequestContext.current&.request&.env&.dig(ENV_USER_ID_KEY)
  end

  # Check Current attributes (for background job support)
  def self.current_visitor_id
    defined?(Current) ? Current.visitor_id : nil
  end
  private_class_method :current_visitor_id

  def self.current_user_id
    defined?(Current) ? Current.user_id : nil
  end
  private_class_method :current_user_id

  # ============================================================================
  # 4-Call Model API
  # ============================================================================

  # Track an event (journey step)
  #
  # @param event_type [String] The name of the event
  # @param visitor_id [String, nil] Explicit visitor ID (required for background jobs)
  # @param properties [Hash] Custom event properties (url, referrer auto-added)
  # @param identifier [Hash, nil] Optional identifier for cross-device identity resolution
  # @return [Hash, false] Result hash on success, false on failure
  #
  # @example Normal usage (within request context)
  #   Mbuzz.event("add_to_cart", product_id: "SKU-123", price: 49.99)
  #
  # @example Background job (must pass explicit visitor_id)
  #   Mbuzz.event("order_processed", visitor_id: order.mbuzz_visitor_id, order_id: order.id)
  #
  # @example With identifier for cross-device tracking
  #   Mbuzz.event("page_view", identifier: { email: "user@example.com" })
  #
  def self.event(event_type, visitor_id: nil, identifier: nil, **properties)
    resolved_visitor_id = visitor_id || self.visitor_id
    resolved_user_id = user_id

    # Must have at least one identifier
    return false unless resolved_visitor_id || resolved_user_id

    Client.track(
      visitor_id: resolved_visitor_id,
      user_id: resolved_user_id,
      event_type: event_type,
      properties: enriched_properties(properties),
      ip: current_ip,
      user_agent: current_user_agent,
      identifier: identifier
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
  # @param visitor_id [String, nil] Explicit visitor ID (required for background jobs)
  # @param revenue [Numeric, nil] Revenue amount
  # @param user_id [String, nil] User ID for acquisition-linked conversions
  # @param is_acquisition [Boolean] Mark this as the acquisition conversion for this user
  # @param inherit_acquisition [Boolean] Inherit attribution from user's acquisition conversion
  # @param identifier [Hash, nil] Optional identifier for cross-device identity resolution
  # @param properties [Hash] Custom properties
  # @return [Hash, false] Result hash on success, false on failure
  #
  # @example Basic conversion (within request context)
  #   Mbuzz.conversion("purchase", revenue: 99.99, order_id: "ORD-123")
  #
  # @example Background job (must pass explicit visitor_id)
  #   Mbuzz.conversion("purchase", visitor_id: order.mbuzz_visitor_id, revenue: 99.99)
  #
  # @example Acquisition conversion (marks signup as THE acquisition moment)
  #   Mbuzz.conversion("signup", user_id: "user_123", is_acquisition: true)
  #
  # @example Recurring revenue (inherits attribution from acquisition)
  #   Mbuzz.conversion("payment", user_id: "user_123", revenue: 49.00, inherit_acquisition: true)
  #
  # @example With identifier for cross-device tracking
  #   Mbuzz.conversion("purchase", identifier: { email: "user@example.com" })
  #
  def self.conversion(conversion_type, visitor_id: nil, revenue: nil, user_id: nil, is_acquisition: false, inherit_acquisition: false, identifier: nil, **properties)
    resolved_visitor_id = visitor_id || self.visitor_id
    resolved_user_id = user_id || self.user_id

    # Must have at least one identifier (visitor_id or user_id)
    return false unless resolved_visitor_id || resolved_user_id

    Client.conversion(
      visitor_id: resolved_visitor_id,
      user_id: resolved_user_id,
      conversion_type: conversion_type,
      revenue: revenue,
      is_acquisition: is_acquisition,
      inherit_acquisition: inherit_acquisition,
      properties: enriched_properties(properties),
      ip: current_ip,
      user_agent: current_user_agent,
      identifier: identifier
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
    result = Client.identify(
      user_id: user_id,
      visitor_id: visitor_id || self.visitor_id,
      traits: traits
    )

    store_user_id_in_context(user_id) if result

    result
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  def self.store_user_id_in_context(uid)
    str_id = uid.to_s
    Current.user_id = str_id if defined?(Current)
    RequestContext.current&.request&.env&.[]=(ENV_USER_ID_KEY, str_id)
  end
  private_class_method :store_user_id_in_context

  def self.enriched_properties(custom_properties)
    return custom_properties unless RequestContext.current

    RequestContext.current.enriched_properties(custom_properties)
  end
  private_class_method :enriched_properties

  def self.current_ip
    current_attributes_ip || RequestContext.current&.ip
  end
  private_class_method :current_ip

  def self.current_user_agent
    current_attributes_user_agent || RequestContext.current&.user_agent
  end
  private_class_method :current_user_agent

  def self.current_attributes_ip
    return nil unless defined?(Current)

    Current.ip
  end
  private_class_method :current_attributes_ip

  def self.current_attributes_user_agent
    return nil unless defined?(Current)

    Current.user_agent
  end
  private_class_method :current_attributes_user_agent
end
