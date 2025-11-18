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
        @request = Rack::Request.new(env)

        env[ENV_VISITOR_ID_KEY] = visitor_id
        env[ENV_USER_ID_KEY] = user_id

        RequestContext.with_context(request: request) do
          app.call(env).tap do |status, headers, body|
            set_visitor_cookie(headers)
          end
        end
      end

      private

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
        headers["Set-Cookie"] = "#{VISITOR_COOKIE_NAME}=#{visitor_id}; Path=#{VISITOR_COOKIE_PATH}; Max-Age=#{VISITOR_COOKIE_MAX_AGE}; HttpOnly; SameSite=#{VISITOR_COOKIE_SAME_SITE}"
      end
    end
  end
end
