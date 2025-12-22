# frozen_string_literal: true

require "rack"

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
        env[ENV_USER_ID_KEY] = context[:user_id]
        env[ENV_SESSION_ID_KEY] = context[:session_id]

        RequestContext.with_context(request: request) do
          create_session_if_new(context, request)

          status, headers, body = @app.call(env)
          set_cookies(headers, context, request)
          [status, headers, body]
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

      private

      # Build all request-specific context as a frozen hash
      # This ensures thread-safety by using local variables only
      def build_request_context(request)
        visitor_id = visitor_id_from_cookie(request) || Visitor::Identifier.generate
        session_id = session_id_from_cookie(request) || generate_session_id
        user_id = user_id_from_session(request)
        new_session = session_id_from_cookie(request).nil?

        {
          visitor_id: visitor_id,
          session_id: session_id,
          user_id: user_id,
          new_session: new_session
        }.freeze
      end

      def visitor_id_from_cookie(request)
        request.cookies[VISITOR_COOKIE_NAME]
      end

      def session_id_from_cookie(request)
        request.cookies[SESSION_COOKIE_NAME]
      end

      def user_id_from_session(request)
        request.session[SESSION_USER_ID_KEY] if request.session
      end

      def generate_session_id
        SecureRandom.hex(32)
      end

      # Session creation

      def create_session_if_new(context, request)
        return unless context[:new_session]

        create_session_async(context, request)
      end

      def create_session_async(context, request)
        # Capture values in local variables for thread safety
        visitor_id = context[:visitor_id]
        session_id = context[:session_id]
        url = request.url
        referrer = request.referer

        Thread.new do
          create_session(visitor_id, session_id, url, referrer)
        end
      end

      def create_session(visitor_id, session_id, url, referrer)
        Client.session(
          visitor_id: visitor_id,
          session_id: session_id,
          url: url,
          referrer: referrer
        )
      rescue => e
        log_session_error(e)
      end

      def log_session_error(error)
        Mbuzz.config.logger&.error("Session creation failed: #{error.message}")
      end

      # Cookie setting

      def set_cookies(headers, context, request)
        set_visitor_cookie(headers, context, request)
        set_session_cookie(headers, context, request)
      end

      def set_visitor_cookie(headers, context, request)
        Rack::Utils.set_cookie_header!(
          headers,
          VISITOR_COOKIE_NAME,
          visitor_cookie_options(context, request)
        )
      end

      def set_session_cookie(headers, context, request)
        Rack::Utils.set_cookie_header!(
          headers,
          SESSION_COOKIE_NAME,
          session_cookie_options(context, request)
        )
      end

      def visitor_cookie_options(context, request)
        base_cookie_options(request).merge(
          value: context[:visitor_id],
          max_age: VISITOR_COOKIE_MAX_AGE
        )
      end

      def session_cookie_options(context, request)
        base_cookie_options(request).merge(
          value: context[:session_id],
          max_age: SESSION_COOKIE_MAX_AGE
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
    end
  end
end
