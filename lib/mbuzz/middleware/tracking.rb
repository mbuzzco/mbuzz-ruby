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

        RequestContext.with_context(request: request) do
          status, headers, body = @app.call(env)
          set_visitor_cookie(headers, context, request)
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
        {
          visitor_id: resolve_visitor_id(request),
          user_id: user_id_from_session(request)
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

      # Cookie setting - only visitor cookie (sessions are server-side)

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
    end
  end
end
