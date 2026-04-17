#!/usr/bin/env ruby
# frozen_string_literal: true

# Paired A/B benchmark comparison for downstream fixtures.
#
# Compares benchmark results between two JSON result files (base vs current)
# using three gate layers:
#   1. Allocation ratio gate  — current_allocs / base_allocs ≤ threshold
#   2. Min-time ratio gate    — min_time(current) / min_time(base) ≤ threshold
#   3. Absolute time gate     — min_time(current) ≤ per-fixture limit
#
# Usage:
#   # Generate base results (on main branch):
#   BENCH_JSON=/tmp/bench_base.json bundle exec ruby tmp/bench/bench_xmi.rb
#
#   # Generate current results (on feature branch):
#   BENCH_JSON=/tmp/bench_current.json bundle exec ruby tmp/bench/bench_xmi.rb
#
#   # Compare:
#   bundle exec ruby tmp/bench/bench_compare.rb /tmp/bench_base.json /tmp/bench_current.json
#
# Exit code: 0 if all gates pass, 1 if any gate fails.

require_relative "gate_config"
require "json"

module BenchCompare
  module_function

  def run(base_path, current_path)
    base = load_results(base_path)
    current = load_results(current_path)

    puts "=" * 90
    puts "Benchmark Gate Comparison"
    puts "=" * 90
    puts "Base:    #{base_path}"
    puts "Current: #{current_path}"
    puts

    # Find common fixtures
    common_labels = base.keys & current.keys
    if common_labels.empty?
      if base.empty? && current.empty?
        puts "WARNING: No benchmark results in either base or current (all fixtures skipped?)."
        puts "Skipping gate comparison."
        exit 0
      else
        warn "ERROR: No common fixtures found between base and current results."
        warn "  Base fixtures:    #{base.keys.join(', ')}"
        warn "  Current fixtures: #{current.keys.join(', ')}"
        exit 1
      end
    end

    any_failure = false
    results = []

    common_labels.sort.each do |label|
      b = base[label]
      c = current[label]
      gate = GateConfig.find_gate(label.to_s)

      result = check_gates(label, b, c, gate)
      results << result
      any_failure = true if result[:failed]
      print_gate_result(result)
    end

    # Report fixtures only in one side
    only_base = base.keys - current.keys
    only_current = current.keys - base.keys
    if only_base.any?
      puts "\n  WARNING: Fixtures only in base: #{only_base.join(', ')}"
    end
    if only_current.any?
      puts "\n  WARNING: Fixtures only in current: #{only_current.join(', ')}"
    end

    puts
    puts "=" * 90
    summary = results.select { |r| r[:failed] }
    if summary.empty?
      puts "ALL GATES PASSED (#{results.size} fixtures)"
    else
      puts "GATES FAILED: #{summary.size}/#{results.size} fixtures"
      summary.each do |r|
        puts "  - #{r[:label]}: #{r[:failures].join(', ')}"
      end
    end
    puts "=" * 90

    exit(1) if any_failure
  end

  def check_gates(label, base, current, gate)
    failures = []

    # Gate 1: Allocation ratio
    alloc_ratio = if base[:allocations].positive?
                    current[:allocations].to_f / base[:allocations]
                  else
                    0.0
                  end
    threshold = gate[:alloc_ratio] || GateConfig::DEFAULT_ALLOC_RATIO
    if alloc_ratio > threshold
      failures << "alloc_ratio: #{format('%.4f', alloc_ratio)} > #{threshold}"
    end

    # Gate 2: Min-time ratio
    time_ratio = if base[:min_time].positive?
                   current[:min_time].to_f / base[:min_time]
                 else
                   0.0
                 end
    threshold = gate[:time_ratio] || GateConfig::DEFAULT_TIME_RATIO
    if time_ratio > threshold
      failures << "time_ratio: #{format('%.4f', time_ratio)} > #{threshold}"
    end

    # Gate 3: Absolute time
    abs_limit = gate[:absolute_max]
    if abs_limit && current[:min_time] > abs_limit
      failures << "absolute: #{format('%.3f',
                                      current[:min_time])}s > #{abs_limit}s"
    end

    {
      label: label,
      base_time: base[:min_time],
      current_time: current[:min_time],
      base_allocs: base[:allocations],
      current_allocs: current[:allocations],
      alloc_ratio: alloc_ratio,
      time_ratio: time_ratio,
      failures: failures,
      failed: failures.any?,
    }
  end

  def print_gate_result(result)
    status = result[:failed] ? "FAIL" : "PASS"
    label = result[:label]

    printf "  %-25s [%s]\n", label, status
    printf "    time:   %.3fs → %.3fs  (ratio: %.3f)\n",
           result[:base_time], result[:current_time], result[:time_ratio]
    printf "    allocs: %d → %d  (ratio: %.4f)\n",
           result[:base_allocs], result[:current_allocs], result[:alloc_ratio]

    result[:failures].each do |f|
      printf "    >>> %s\n", f
    end
    puts
  end

  def load_results(path)
    unless File.exist?(path)
      warn "ERROR: Results file not found: #{path}"
      exit 1
    end

    raw = JSON.parse(File.read(path), symbolize_names: true)
    # Normalize symbol/string keys — JSON keys come as strings
    raw.each_with_object({}) do |(k, v), h|
      h[k.to_s] = v
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 2
    warn "Usage: #{$PROGRAM_NAME} <base_results.json> <current_results.json>"
    warn ""
    warn "Generate result files with: BENCH_JSON=/tmp/results.json bundle exec ruby tmp/bench/bench_xmi.rb"
    exit 1
  end

  BenchCompare.run(ARGV[0], ARGV[1])
end
