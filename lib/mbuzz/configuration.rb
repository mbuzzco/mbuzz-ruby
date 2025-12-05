# frozen_string_literal: true

module Mbuzz
  class ConfigurationError < StandardError; end

  class Configuration
    attr_accessor :api_key, :api_url, :enabled, :debug, :timeout, :batch_size, :flush_interval, :logger,
      :skip_paths, :skip_extensions

    # Default paths to skip - health checks, assets, etc.
    DEFAULT_SKIP_PATHS = %w[
      /up
      /health
      /healthz
      /ping
      /cable
      /assets
      /packs
      /rails/active_storage
      /api
    ].freeze

    # Default extensions to skip - static assets
    DEFAULT_SKIP_EXTENSIONS = %w[
      .js .css .map .png .jpg .jpeg .gif .ico .svg .woff .woff2 .ttf .eot .webp
    ].freeze

    def initialize
      @api_url = "https://mbuzz.co/api/v1"
      @enabled = true
      @debug = false
      @timeout = 5
      @batch_size = 50
      @flush_interval = 30
      @skip_paths = []
      @skip_extensions = []
    end

    def validate!
      raise ConfigurationError, "api_key is required" if api_key.nil? || api_key.empty?
    end

    def all_skip_paths
      DEFAULT_SKIP_PATHS + Array(skip_paths)
    end

    def all_skip_extensions
      DEFAULT_SKIP_EXTENSIONS + Array(skip_extensions)
    end
  end
end
