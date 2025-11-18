# frozen_string_literal: true

require "test_helper"

class Mbuzz::RailtieTest < Minitest::Test
  def test_railtie_file_exists
    assert File.exist?(File.expand_path("../../lib/mbuzz/railtie.rb", __dir__))
  end

  def test_railtie_loads_when_rails_available
    skip "Rails not available - Railtie only loads in Rails environment"
    assert defined?(Mbuzz::Railtie)
  end
end
