# frozen_string_literal: true

module Mbuzz
  # Meta's browser id, written client-side by the customer's Meta Pixel. Read
  # only, never set: forwarded on the session call so Meta can merge mbuzz's
  # server event with the Pixel's browser event.
  module Fbp
    # Meta's documented shape, fb.<subdomainIndex>.<creationTime>.<random>, plus
    # the optional appendix Meta's server-side Parameter Builder adds
    # (fb.1.<ts>.<random>.AQECAQIB). Both are valid to Meta. \A…\z, not ^…$:
    # `$` matches before a trailing newline.
    FORMAT = /\Afb\.\d+\.\d+\.\d+(?:\.[A-Za-z0-9_-]+)?\z/

    # The Pixel's _fbp, or nil when absent or not in Meta's format. mbuzz never
    # invents one and never rewrites what it forwards.
    def self.read(value)
      value if value.is_a?(String) && FORMAT.match?(value)
    end
  end
end
