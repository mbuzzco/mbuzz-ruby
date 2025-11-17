# frozen_string_literal: true

require "test_helper"

class Mbuzz::Visitor::IdentifierTest < Minitest::Test
  def test_generate_returns_64_character_hex_string
    visitor_id = Mbuzz::Visitor::Identifier.generate
    assert_match(/\A[0-9a-f]{64}\z/, visitor_id)
  end

  def test_generate_returns_unique_ids
    id1 = Mbuzz::Visitor::Identifier.generate
    id2 = Mbuzz::Visitor::Identifier.generate
    refute_equal id1, id2
  end
end
