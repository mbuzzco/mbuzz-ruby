# frozen_string_literal: true

module Mbuzz
  class Railtie < Rails::Railtie
    initializer "mbuzz.configure_rails" do |app|
      # The endpoint must sit ahead of Tracking: it answers its own path and
      # never falls through, so Tracking should not also process it.
      app.middleware.use Mbuzz::Middleware::SessionEndpoint
      app.middleware.use Mbuzz::Middleware::Tracking

      ActiveSupport.on_load(:action_controller) do
        include Mbuzz::ControllerHelpers
      end
    end
  end
end
