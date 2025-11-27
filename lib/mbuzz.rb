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
  ALIAS_PATH = "/alias"
  CONVERSIONS_PATH = "/conversions"

  VISITOR_COOKIE_NAME = "mbuzz_visitor_id"
  VISITOR_COOKIE_MAX_AGE = 60 * 60 * 24 * 365 * 2 # 2 years
  VISITOR_COOKIE_PATH = "/"
  VISITOR_COOKIE_SAME_SITE = "Lax"

  SESSION_USER_ID_KEY = "user_id"
  ENV_USER_ID_KEY = "mbuzz.user_id"
  ENV_VISITOR_ID_KEY = "mbuzz.visitor_id"

  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield(config)
  end

  def self.visitor_id
    RequestContext.current&.request&.env&.dig(ENV_VISITOR_ID_KEY)
  end

  def self.user_id
    RequestContext.current&.request&.env&.dig(ENV_USER_ID_KEY)
  end

  def self.track(event_type, properties: {})
    Client.track(
      visitor_id: visitor_id,
      user_id: user_id,
      event_type: event_type,
      properties: properties
    )
  end

  def self.conversion(conversion_type, revenue: nil, properties: {})
    Client.conversion(
      visitor_id: visitor_id,
      conversion_type: conversion_type,
      revenue: revenue,
      properties: properties
    )
  end
end
