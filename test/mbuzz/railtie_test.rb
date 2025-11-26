# frozen_string_literal: true

require "test_helper"

class Mbuzz::RailtieTest < Minitest::Test
  def test_railtie_file_exists
    assert File.exist?(File.expand_path("../../lib/mbuzz/railtie.rb", __dir__))
  end
end
