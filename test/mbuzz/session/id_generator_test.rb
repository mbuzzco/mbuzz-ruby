# frozen_string_literal: true

require "test_helper"

class Mbuzz::Session::IdGeneratorTest < Minitest::Test
  # --- generate_deterministic tests ---

  def test_generate_deterministic_returns_64_char_hex_string
    result = generator.generate_deterministic(visitor_id: sample_visitor_id, timestamp: sample_timestamp)
    assert_match(/\A[0-9a-f]{64}\z/, result)
  end

  def test_generate_deterministic_is_consistent
    result1 = generator.generate_deterministic(visitor_id: sample_visitor_id, timestamp: sample_timestamp)
    result2 = generator.generate_deterministic(visitor_id: sample_visitor_id, timestamp: sample_timestamp)
    assert_equal result1, result2
  end

  def test_generate_deterministic_same_within_time_bucket
    # Within same 30-minute bucket (1800 seconds)
    # bucket = timestamp / 1800
    # 1735500000 / 1800 = 964166
    # 1735500599 / 1800 = 964166 (last second of bucket)
    timestamp1 = 1735500000
    timestamp2 = 1735500001  # 1 second later
    timestamp3 = 1735500599  # last second of bucket

    result1 = generator.generate_deterministic(visitor_id: sample_visitor_id, timestamp: timestamp1)
    result2 = generator.generate_deterministic(visitor_id: sample_visitor_id, timestamp: timestamp2)
    result3 = generator.generate_deterministic(visitor_id: sample_visitor_id, timestamp: timestamp3)

    assert_equal result1, result2, "Same session ID within time bucket"
    assert_equal result1, result3, "Same session ID within time bucket"
  end

  def test_generate_deterministic_different_across_time_buckets
    timestamp1 = 1735500000
    timestamp2 = 1735501800  # Exactly 30 minutes later (next bucket)

    result1 = generator.generate_deterministic(visitor_id: sample_visitor_id, timestamp: timestamp1)
    result2 = generator.generate_deterministic(visitor_id: sample_visitor_id, timestamp: timestamp2)

    refute_equal result1, result2, "Different session ID in different time bucket"
  end

  def test_generate_deterministic_different_for_different_visitors
    result1 = generator.generate_deterministic(visitor_id: "visitor_a", timestamp: sample_timestamp)
    result2 = generator.generate_deterministic(visitor_id: "visitor_b", timestamp: sample_timestamp)

    refute_equal result1, result2, "Different visitors get different session IDs"
  end

  # --- generate_from_fingerprint tests ---

  def test_generate_from_fingerprint_returns_64_char_hex_string
    result = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: sample_user_agent,
      timestamp: sample_timestamp
    )
    assert_match(/\A[0-9a-f]{64}\z/, result)
  end

  def test_generate_from_fingerprint_is_consistent
    result1 = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: sample_user_agent,
      timestamp: sample_timestamp
    )
    result2 = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: sample_user_agent,
      timestamp: sample_timestamp
    )

    assert_equal result1, result2
  end

  def test_generate_from_fingerprint_same_within_time_bucket
    timestamp1 = 1735500000
    timestamp2 = 1735500001

    result1 = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: sample_user_agent,
      timestamp: timestamp1
    )
    result2 = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: sample_user_agent,
      timestamp: timestamp2
    )

    assert_equal result1, result2, "Same session ID within time bucket"
  end

  def test_generate_from_fingerprint_different_across_time_buckets
    timestamp1 = 1735500000
    timestamp2 = 1735501800

    result1 = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: sample_user_agent,
      timestamp: timestamp1
    )
    result2 = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: sample_user_agent,
      timestamp: timestamp2
    )

    refute_equal result1, result2, "Different session ID in different time bucket"
  end

  def test_generate_from_fingerprint_different_for_different_ips
    result1 = generator.generate_from_fingerprint(
      client_ip: "192.168.1.1",
      user_agent: sample_user_agent,
      timestamp: sample_timestamp
    )
    result2 = generator.generate_from_fingerprint(
      client_ip: "192.168.1.2",
      user_agent: sample_user_agent,
      timestamp: sample_timestamp
    )

    refute_equal result1, result2, "Different IPs get different session IDs"
  end

  def test_generate_from_fingerprint_different_for_different_user_agents
    result1 = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: "Mozilla/5.0 Chrome",
      timestamp: sample_timestamp
    )
    result2 = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: "Mozilla/5.0 Safari",
      timestamp: sample_timestamp
    )

    refute_equal result1, result2, "Different user agents get different session IDs"
  end

  # --- generate_random tests ---

  def test_generate_random_returns_64_char_hex_string
    result = generator.generate_random
    assert_match(/\A[0-9a-f]{64}\z/, result)
  end

  def test_generate_random_returns_unique_ids
    result1 = generator.generate_random
    result2 = generator.generate_random
    refute_equal result1, result2
  end

  # --- Cross-method tests ---

  def test_deterministic_and_fingerprint_produce_different_ids
    # Even with same timestamp, different generation methods should produce different IDs
    deterministic = generator.generate_deterministic(
      visitor_id: sample_visitor_id,
      timestamp: sample_timestamp
    )
    fingerprint = generator.generate_from_fingerprint(
      client_ip: sample_ip,
      user_agent: sample_user_agent,
      timestamp: sample_timestamp
    )

    refute_equal deterministic, fingerprint
  end

  private

  def generator
    Mbuzz::Session::IdGenerator
  end

  def sample_visitor_id
    "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
  end

  def sample_timestamp
    1735500000
  end

  def sample_ip
    "203.0.113.42"
  end

  def sample_user_agent
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
  end
end
