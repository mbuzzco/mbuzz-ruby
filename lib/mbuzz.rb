# frozen_string_literal: true

require_relative "mbuzz/version"
require_relative "mbuzz/configuration"
require_relative "mbuzz/visitor/identifier"
require_relative "mbuzz/request_context"
require_relative "mbuzz/api"

module Mbuzz
  class Error < StandardError; end

  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield(config)
  end
end
