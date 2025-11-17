# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "mbuzz"

# Disable minitest plugins to avoid loading Rails
ENV["MT_NO_PLUGINS"] = "1"

require "minitest/autorun"
