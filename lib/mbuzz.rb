# frozen_string_literal: true

require_relative "mbuzz/version"
require_relative "mbuzz/configuration"
require_relative "mbuzz/visitor/identifier"
require_relative "mbuzz/request_context"
require_relative "mbuzz/api"
require_relative "mbuzz/client"

module Mbuzz
  class Error < StandardError; end

  EVENTS_PATH = "/events"
  IDENTIFY_PATH = "/identify"
  ALIAS_PATH = "/alias"

  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield(config)
  end
end
