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
      @api_url = DEFAULT_API_URL
      @enabled = true
      @debug = false
      @timeout = 5
      @batch_size = 50
      @flush_interval = 30
      @skip_paths = []
      @skip_extensions = []
    end

    DEFAULT_API_URL = "https://api.mbuzz.co/api/v1"
    REGION_KEY = /\Ask_[a-z]+_[a-z]{2}_/

    # api_url is an explicit opt-in for data-resident installs (spec M9). https
    # only; no api_url means api.mbuzz.co, always; a region key (sk_live_au_...)
    # must be paired with api_url and api_url with a region key; test keys are
    # exempt from the pairing. There is no fallback host: a failed request is
    # dropped, never retried against api.mbuzz.co.
    def self.resolve_api_url(api_key, api_url)
      has_url = !api_url.to_s.empty?
      raise ConfigurationError, "api_url must start with https://" if has_url && !api_url.start_with?("https://")

      unless api_key.to_s.start_with?("sk_test_") || has_url == REGION_KEY.match?(api_key.to_s)
        raise ConfigurationError, "api_url and the API key region must be set together: " \
          "a region key needs api_url, and api_url needs a region key"
      end

      (has_url ? api_url : DEFAULT_API_URL).chomp("/")
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
