# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

class GemPackagingTest < Minitest::Test
  def test_built_gem_is_requireable
    Dir.mktmpdir do |tmpdir|
      gem_file = Dir.glob("*.gem").first || build_gem
      install_dir = File.join(tmpdir, "gems")

      # Install gem to temp directory
      system("gem install #{gem_file} --install-dir #{install_dir} --no-document --quiet")

      # Try to require it
      result = system("ruby", "-I#{install_dir}/gems/mbuzz-*/lib", "-e", "require 'mbuzz'")

      assert result, "Built gem should be requireable without errors"
    end
  end

  private

  def build_gem
    system("gem build mbuzz.gemspec --quiet")
    Dir.glob("*.gem").first
  end
end
