# frozen_string_literal: true

module Mbuzz
  # CurrentAttributes for automatic background job context propagation.
  #
  # Rails automatically serializes CurrentAttributes into ActiveJob payloads
  # and restores them when jobs execute. This means visitor_id captured during
  # the original request is available in background jobs without any manual
  # passing or database storage.
  #
  # How it works:
  #   1. Middleware captures visitor_id from cookie
  #   2. Stores in Mbuzz::Current.visitor_id
  #   3. Controller enqueues background job
  #   4. Rails serializes Current attributes into job payload
  #   5. Job runs on different thread/process
  #   6. Rails restores Current.visitor_id before job executes
  #   7. Mbuzz.event/conversion reads from Current.visitor_id
  #
  # This is why customers don't need to store visitor_id in their database.
  #
  class Current < ActiveSupport::CurrentAttributes
    attribute :visitor_id
    attribute :session_id
    attribute :user_id
    attribute :ip
    attribute :user_agent
  end
end
