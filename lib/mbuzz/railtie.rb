# frozen_string_literal: true

module Mbuzz
  class Railtie < Rails::Railtie
    initializer "mbuzz.configure_rails" do |app|
      app.middleware.use Mbuzz::Middleware::Tracking

      ActiveSupport.on_load(:action_controller) do
        include Mbuzz::ControllerHelpers
      end
    end
  end
end
