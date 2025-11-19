# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "openssl"

module Mbuzz
  class Api
    def self.post(path, payload)
      return false unless enabled_and_configured?

      response = http_client(path).request(build_request(path, payload))
      success?(response)
    rescue ConfigurationError, Net::ReadTimeout, Net::OpenTimeout, Net::HTTPError => e
      log_error("#{e.class}: #{e.message}")
      false
    end

    def self.enabled_and_configured?
      return false unless config.enabled
      config.validate!
      true
    rescue ConfigurationError => e
      log_error(e.message)
      false
    end
    private_class_method :enabled_and_configured?

    def self.http_client(path)
      uri = URI.join(config.api_url, path)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        if uri.scheme == "https"
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
        http.open_timeout = config.timeout
        http.read_timeout = config.timeout
      end
    end
    private_class_method :http_client

    def self.build_request(path, payload)
      uri = URI.join(config.api_url, path)
      Net::HTTP::Post.new(uri.path).tap do |request|
        request["Authorization"] = "Bearer #{config.api_key}"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "mbuzz-ruby/#{VERSION}"
        request.body = JSON.generate(payload)
      end
    end
    private_class_method :build_request

    def self.success?(response)
      return true if response.code.to_i.between?(200, 299)

      log_error("API #{response.code}: #{response.body}")
      false
    end
    private_class_method :success?

    def self.log_error(message)
      warn "[mbuzz] #{message}" if config.debug
    end
    private_class_method :log_error

    def self.config
      Mbuzz.config
    end
    private_class_method :config
  end
end
