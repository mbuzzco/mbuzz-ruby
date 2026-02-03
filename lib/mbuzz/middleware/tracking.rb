# frozen_string_literal: true

require "rack"
require "digest"
require "securerandom"

module Mbuzz
  module Middleware
    class Tracking
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) if skip_request?(env)

        request = Rack::Request.new(env)
        context = build_request_context(request)

        env[ENV_VISITOR_ID_KEY] = context[:visitor_id]
        env[ENV_SESSION_ID_KEY] = context[:session_id]
        env[ENV_USER_ID_KEY] = context[:user_id]

        store_in_current_attributes(context, request)

        create_session_async(context, request) if should_create_session?(env)

        RequestContext.with_context(request: request) do
          status, headers, body = @app.call(env)
          set_visitor_cookie(headers, context, request)
          [status, headers, body]
        ensure
          reset_current_attributes
        end
      end

      # Path filtering - skip health checks, static assets, etc.

      def skip_request?(env)
        path = env["PATH_INFO"].to_s.downcase

        skip_by_path?(path) || skip_by_extension?(path)
      end

      def skip_by_path?(path)
        Mbuzz.config.all_skip_paths.any? { |skip| path.start_with?(skip) }
      end

      def skip_by_extension?(path)
        Mbuzz.config.all_skip_extensions.any? { |ext| path.end_with?(ext) }
      end

      # Navigation detection — only create sessions for real page navigations.
      # Sec-Fetch-* headers (browser-enforced, unforgeable) are the primary signal;
      # framework-specific blacklist covers old browsers and bots.

      def should_create_session?(env)
        return page_navigation?(env) if sec_fetch_headers?(env)

        !framework_sub_request?(env)
      end

      def sec_fetch_headers?(env)
        !env["HTTP_SEC_FETCH_MODE"].nil?
      end

      def page_navigation?(env)
        env["HTTP_SEC_FETCH_MODE"] == "navigate" &&
          env["HTTP_SEC_FETCH_DEST"] == "document" &&
          env["HTTP_SEC_PURPOSE"].nil?
      end

      def framework_sub_request?(env)
        !env["HTTP_TURBO_FRAME"].nil? ||
          !env["HTTP_HX_REQUEST"].nil? ||
          !env["HTTP_X_UP_VERSION"].nil? ||
          env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
      end

      private

      # Build all request-specific context as a frozen hash.
      # Thread-safety: all values needed by async session creation are captured here,
      # NOT accessed from the request object in the background thread.
      def build_request_context(request)
        ip = extract_ip(request)
        user_agent = request.user_agent.to_s

        {
          visitor_id: resolve_visitor_id(request),
          session_id: SecureRandom.uuid,
          user_id: user_id_from_session(request),
          url: request.url,
          referrer: request.referer,
          ip: ip,
          user_agent: user_agent,
          device_fingerprint: Digest::SHA256.hexdigest("#{ip}|#{user_agent}")[0, 32]
        }.freeze
      end

      def resolve_visitor_id(request)
        visitor_id_from_cookie(request) || Visitor::Identifier.generate
      end

      def visitor_id_from_cookie(request)
        request.cookies[VISITOR_COOKIE_NAME]
      end

      def user_id_from_session(request)
        request.session[SESSION_USER_ID_KEY] if request.session
      end

      # Session creation - async to not block request
      # IMPORTANT: This runs in a background thread. All data must come from
      # the context hash, NOT from the request object (which may be invalid)

      def create_session_async(context, _request)
        Thread.new do
          create_session(context)
        rescue StandardError => e
          log_error("Session creation failed: #{e.message}") if Mbuzz.config.debug
        end
      end

      def create_session(context)
        Client.session(
          visitor_id: context[:visitor_id],
          session_id: context[:session_id],
          url: context[:url],
          referrer: context[:referrer],
          device_fingerprint: context[:device_fingerprint]
        )
      end

      def log_error(message)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.error("[Mbuzz] #{message}")
      end

      # Cookie setting - visitor identity only (sessions are server-side)

      def set_visitor_cookie(headers, context, request)
        Rack::Utils.set_cookie_header!(
          headers,
          VISITOR_COOKIE_NAME,
          visitor_cookie_options(context, request)
        )
      end

      def visitor_cookie_options(context, request)
        base_cookie_options(request).merge(
          value: context[:visitor_id],
          max_age: VISITOR_COOKIE_MAX_AGE
        )
      end

      def base_cookie_options(request)
        options = {
          path: VISITOR_COOKIE_PATH,
          httponly: true,
          same_site: VISITOR_COOKIE_SAME_SITE
        }
        options[:secure] = true if request.ssl?
        options
      end

      # Store context in CurrentAttributes for background job propagation
      def store_in_current_attributes(context, request)
        return unless defined?(Mbuzz::Current)

        Mbuzz::Current.visitor_id = context[:visitor_id]
        Mbuzz::Current.session_id = context[:session_id]
        Mbuzz::Current.user_id = context[:user_id]
        Mbuzz::Current.ip = extract_ip(request)
        Mbuzz::Current.user_agent = request.user_agent
      end

      def reset_current_attributes
        return unless defined?(Mbuzz::Current)

        Mbuzz::Current.reset
      end

      def extract_ip(request)
        forwarded = request.env["HTTP_X_FORWARDED_FOR"]
        return forwarded.split(",").first.strip if forwarded

        request.ip
      end
    end
  end
end
