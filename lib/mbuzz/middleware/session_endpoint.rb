# frozen_string_literal: true

require "rack"
require "json"
require "digest"
require "securerandom"

module Mbuzz
  module Middleware
    # Establishes the visitor from a page a cache served.
    #
    # A cached page never enters the Rack stack, so Tracking never runs and no
    # visitor cookie is set — every later event is then rejected for having no
    # one to attribute it to, silently, while the page renders perfectly.
    #
    # This endpoint is the one request on such a page that always reaches the
    # app. A small script on the page POSTs here; the SERVER mints the cookie on
    # the response. The id is never created or read in JS, so it stays HttpOnly
    # and keeps its full two-year life — a cookie written by document.cookie is
    # capped at 7 days under Safari's ITP, and 24 hours after an ad click.
    #
    # Mount ahead of Tracking:
    #
    #   config.middleware.insert_before Mbuzz::Middleware::Tracking,
    #                                   Mbuzz::Middleware::SessionEndpoint
    class SessionEndpoint
      # Nothing to return: the response exists for its Set-Cookie header.
      NO_CONTENT_STATUS = 204

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless session_request?(env)

        mint(Rack::Request.new(env))
      end

      private

      # POST only: a GET is cacheable by an intermediary, which would reintroduce
      # the very bug this endpoint exists to fix.
      def session_request?(env)
        env["REQUEST_METHOD"] == "POST" &&
          env["PATH_INFO"].to_s == SESSION_ENDPOINT_PATH
      end

      def mint(request)
        context = build_context(request)
        create_session_async(context)

        [NO_CONTENT_STATUS, response_headers(context, request), []]
      end

      def build_context(request)
        payload    = parse_body(request)
        ip         = extract_ip(request)
        user_agent = request.user_agent.to_s

        {
          visitor_id: resolve_visitor_id(request),
          session_id: SecureRandom.uuid,
          # The page's URL, not ours — a script on the page called us, so our own
          # path would attribute every session to this endpoint.
          url: payload["url"],
          referrer: payload["referrer"],
          ip: ip,
          user_agent: user_agent,
          device_fingerprint: Digest::SHA256.hexdigest("#{ip}|#{user_agent}")[0, 32]
        }.freeze
      end

      def parse_body(request)
        body = request.body&.read.to_s
        return {} if body.empty?

        parsed = JSON.parse(body)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def resolve_visitor_id(request)
        request.cookies[VISITOR_COOKIE_NAME] || Visitor::Identifier.generate
      end

      def create_session_async(context)
        Thread.new do
          Client.session(
            visitor_id: context[:visitor_id],
            session_id: context[:session_id],
            url: context[:url],
            referrer: context[:referrer],
            device_fingerprint: context[:device_fingerprint],
            user_agent: context[:user_agent],
            ip: context[:ip]
          )
        rescue StandardError => e
          log_error("Session creation failed: #{e.message}") if Mbuzz.config.debug
        end
      end

      def response_headers(context, request)
        headers = { "cache-control" => "no-store, no-cache, must-revalidate, private" }
        Rack::Utils.set_cookie_header!(headers, VISITOR_COOKIE_NAME, cookie_options(context, request))
        headers
      end

      def cookie_options(context, request)
        options = {
          value: context[:visitor_id],
          max_age: VISITOR_COOKIE_MAX_AGE,
          path: VISITOR_COOKIE_PATH,
          httponly: true,
          same_site: VISITOR_COOKIE_SAME_SITE
        }
        options[:secure] = true if request.ssl?
        options
      end

      def extract_ip(request)
        forwarded = request.env["HTTP_X_FORWARDED_FOR"]
        return forwarded.split(",").first.strip if forwarded

        request.ip
      end

      def log_error(message)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.error("[Mbuzz] #{message}")
      end
    end
  end
end
