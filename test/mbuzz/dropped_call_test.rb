# frozen_string_literal: true

require "test_helper"
require "stringio"

module Mbuzz
  # The bug this guards against is silence, so these tests assert on what is
  # actually emitted - not merely that the call returned false.
  class DroppedCallTest < Minitest::Test
    def setup
      Mbuzz.init(api_key: "sk_test_x")
      Mbuzz.config.debug = false
    end

    def test_event_without_any_identity_warns
      output = capture_warnings { Mbuzz.event("signup") }

      assert_includes output, "[mbuzz]"
      assert_includes output, "dropped event"
      assert_includes output, "no visitor_id and no user_id"
    end

    def test_conversion_without_any_identity_warns
      output = capture_warnings { Mbuzz.conversion("purchase", revenue: 10) }

      assert_includes output, "dropped conversion"
      assert_includes output, "no visitor_id and no user_id"
    end

    def test_warning_names_the_dropped_call_so_it_can_be_found
      output = capture_warnings { Mbuzz.event("checkout_started") }

      assert_includes output, "checkout_started"
    end

    def test_warning_points_at_the_cache_fix
      output = capture_warnings { Mbuzz.event("signup") }

      assert_includes output, SESSION_ENDPOINT_PATH,
        "the warning must name the endpoint that fixes the cached-page case"
    end

    # The whole point: the customers who hit this are the ones NOT in debug.
    def test_warning_is_not_gated_behind_debug
      Mbuzz.config.debug = false

      refute_empty capture_warnings { Mbuzz.event("signup") },
        "a debug-gated warning is silent for exactly the people who need it"
    end

    def test_a_valid_call_warns_nothing
      output = capture_warnings do
        Mbuzz::Api.stub(:post_with_response, nil) do
          Mbuzz.event("signup", visitor_id: "vis_abc")
        end
      end

      refute_includes output, "dropped event"
    end

    private

    def capture_warnings
      original = $stderr
      $stderr = StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = original
    end
  end
end
