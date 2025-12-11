# frozen_string_literal: true

require "rack"

module Mbuzz
  module Middleware
    class Tracking
      attr_reader :app, :request

      def initialize(app)
        @app = app
      end

      def call(env)
        return app.call(env) if skip_request?(env)

        reset_request_state!
        @request = Rack::Request.new(env)

        env[ENV_VISITOR_ID_KEY] = visitor_id
        env[ENV_USER_ID_KEY] = user_id
        env[ENV_SESSION_ID_KEY] = session_id

        RequestContext.with_context(request: request) do
          create_session_if_new

          status, headers, body = app.call(env)
          set_visitor_cookie(headers)
          set_session_cookie(headers)
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

      def reset_request_state!
        @request = nil
        @visitor_id = nil
        @session_id = nil
        @user_id = nil
      end

      def visitor_id
        @visitor_id ||= visitor_id_from_cookie || Visitor::Identifier.generate
      end

      def visitor_id_from_cookie
        request.cookies[VISITOR_COOKIE_NAME]
      end

      def user_id
        @user_id ||= user_id_from_session
      end

      def user_id_from_session
        request.session[SESSION_USER_ID_KEY] if request.session
      end

      def set_visitor_cookie(headers)
        Rack::Utils.set_cookie_header!(headers, VISITOR_COOKIE_NAME, visitor_cookie_options)
      end

      def visitor_cookie_options
        base_cookie_options.merge(
          value: visitor_id,
          max_age: VISITOR_COOKIE_MAX_AGE
        )
      end

      # Session ID management

      def session_id
        @session_id ||= session_id_from_cookie || generate_session_id
      end

      def session_id_from_cookie
        request.cookies[SESSION_COOKIE_NAME]
      end

      def generate_session_id
        SecureRandom.hex(32)
      end

      def new_session?
        session_id_from_cookie.nil?
      end

      # Session creation

      def create_session_if_new
        return unless new_session?

        create_session_async
      end

      def create_session_async
        Thread.new { create_session }
      end

      def create_session
        Client.session(
          visitor_id: visitor_id,
          session_id: session_id,
          url: request.url,
          referrer: request.referer
        )
      rescue => e
        log_session_error(e)
      end

      def log_session_error(error)
        Mbuzz.config.logger&.error("Session creation failed: #{error.message}")
      end

      # Session cookie

      def set_session_cookie(headers)
        Rack::Utils.set_cookie_header!(headers, SESSION_COOKIE_NAME, session_cookie_options)
      end

      def session_cookie_options
        base_cookie_options.merge(
          value: session_id,
          max_age: SESSION_COOKIE_MAX_AGE
        )
      end

      # Shared cookie options

      def base_cookie_options
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
