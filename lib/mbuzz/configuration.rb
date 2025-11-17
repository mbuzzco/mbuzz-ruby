# frozen_string_literal: true

module Mbuzz
  class ConfigurationError < StandardError; end

  class Configuration
    attr_accessor :api_key, :api_url, :enabled, :debug, :timeout, :batch_size, :flush_interval

    def initialize
      @api_url = "https://mbuzz.co/api/v1"
      @enabled = true
      @debug = false
      @timeout = 5
      @batch_size = 50
      @flush_interval = 30
    end

    def validate!
      raise ConfigurationError, "api_key is required" if api_key.nil? || api_key.empty?
    end
  end
end
