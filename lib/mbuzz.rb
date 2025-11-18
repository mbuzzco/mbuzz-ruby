# frozen_string_literal: true

require_relative "mbuzz/version"
require_relative "mbuzz/configuration"
require_relative "mbuzz/visitor/identifier"
require_relative "mbuzz/request_context"
require_relative "mbuzz/api"
require_relative "mbuzz/client"
require_relative "mbuzz/middleware/tracking"
require_relative "mbuzz/controller_helpers"

module Mbuzz
  class Error < StandardError; end

  EVENTS_PATH = "/events"
  IDENTIFY_PATH = "/identify"
  ALIAS_PATH = "/alias"

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
end
