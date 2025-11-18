# frozen_string_literal: true

module Mbuzz
  module ControllerHelpers
    def mbuzz_track(event, properties: {})
      Client.track(
        user_id: mbuzz_user_id,
        visitor_id: mbuzz_visitor_id,
        event: event,
        properties: properties
      )
    end

    def mbuzz_identify(traits: {})
      Client.identify(
        user_id: mbuzz_user_id,
        traits: traits
      )
    end

    def mbuzz_alias
      Client.alias(
        user_id: mbuzz_user_id,
        visitor_id: mbuzz_visitor_id
      )
    end

    def mbuzz_user_id
      request.env[ENV_USER_ID_KEY]
    end

    def mbuzz_visitor_id
      request.env[ENV_VISITOR_ID_KEY]
    end
  end
end
