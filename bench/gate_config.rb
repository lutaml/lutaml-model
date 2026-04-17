# frozen_string_literal: true

# Centralized gate configuration for downstream benchmark gating.
#
# Three gate layers:
#   1. alloc_ratio  — current_allocs / base_allocs  (deterministic, load-independent)
#   2. time_ratio   — min_time(current) / min_time(base)  (cancels load noise)
#   3. absolute_max — min_time against per-fixture limit  (safety net)
#
# If no base comparison is available, only the absolute_max gate applies.

module GateConfig
  # Default thresholds applied when not overridden per-downstream
  DEFAULT_ALLOC_RATIO = 1.05  # max 5% more allocations vs base
  DEFAULT_TIME_RATIO  = 1.15  # max 15% slower vs base

  # Primary fixture for each downstream (used as gate key)
  # Format: { downstream_name => { fixture_label => config } }
  GATES = {
    xmi: {
      "ea251" => {
        file: "ea-xmi-2.5.1.xmi",
        alloc_ratio: 1.05,
        time_ratio: 1.15,
        absolute_max: 0.50,
      },
      "large" => {
        file: "full-242.xmi",
        alloc_ratio: 1.05,
        time_ratio: 1.15,
        absolute_max: 10.0,
      },
    },
    sts: {
      "iso-13849-1MB" => {
        alloc_ratio: 1.05,
        time_ratio: 1.15,
        absolute_max: 5.0,
      },
    },
    mml: {
      "complex3-567KB" => {
        alloc_ratio: 1.05,
        time_ratio: 1.15,
        absolute_max: 3.0,
      },
    },
    niso: {
      "pnas-152KB" => {
        alloc_ratio: 1.05,
        time_ratio: 1.15,
        absolute_max: 1.0,
      },
    },
    uniword: {
      "iso690" => {
        alloc_ratio: 1.05,
        time_ratio: 1.15,
        absolute_max: 60.0,
      },
    },
  }.freeze

  module_function

  # Find gate config for a fixture label across all downstreams.
  # Returns the gate config hash or a default.
  def find_gate(fixture_label)
    GATES.each_value do |fixtures|
      return fixtures[fixture_label] if fixtures.key?(fixture_label)
    end

    # Default gate for unregistered fixtures
    {
      alloc_ratio: DEFAULT_ALLOC_RATIO,
      time_ratio: DEFAULT_TIME_RATIO,
      absolute_max: nil, # no absolute gate if not configured
    }
  end

  # All registered fixture labels (for reporting)
  def all_gate_labels
    GATES.flat_map { |_name, fixtures| fixtures.keys }
  end
end
