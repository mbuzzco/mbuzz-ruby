# frozen_string_literal: true

module Mbuzz
  # Says out loud when a call is dropped for having nothing to attribute it to.
  #
  # Every SDK guarded its send with a bare `return false unless valid?`: no
  # request, no log, nothing. Behind a full-page cache that is the whole failure
  # — the cookie is never minted, so every later event fails this guard and
  # vanishes. It cost a full day on a live account precisely because the silence
  # was total from both sides.
  #
  # Deliberately NOT behind config.debug. The customers who hit this are exactly
  # the ones not running in debug, so a debug-gated warning would be silent for
  # everyone who needs it.
  module DroppedCall
    # Built lazily: SESSION_ENDPOINT_PATH is defined in mbuzz.rb *after* this
    # file is required, so interpolating it at load time would not resolve.
    def self.missing_identity
      "no visitor_id and no user_id. If your pages are served from a full-page " \
        "cache, mount Mbuzz::Middleware::SessionEndpoint and call POST " \
        "#{SESSION_ENDPOINT_PATH} from the page — see the README's " \
        "\"Full-page caching\" section."
    end

    def self.warn_missing_identity(kind, name)
      emit("dropped #{kind} #{name.inspect}: #{missing_identity}")
    end

    def self.warn_invalid(kind, name, reason)
      emit("dropped #{kind} #{name.inspect}: #{reason}.")
    end

    def self.emit(message)
      text = "[mbuzz] #{message}"
      return Rails.logger.warn(text) if defined?(Rails) && Rails.logger

      Kernel.warn(text)
    end
    private_class_method :emit
  end
end
