# frozen_string_literal: true

require "securerandom"

module Mbuzz
  module Visitor
    class Identifier
      def self.generate
        SecureRandom.hex(32)
      end
    end
  end
end
