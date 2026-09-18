#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: STS Ruby (ISO/NISO STS document parsing)
# Gate: parse time < 2.0s for ISO-13849-1MB
#
# Usage:
#   STS_DIR=/path/to/sts-ruby ITERATIONS=5 bundle exec ruby tmp/bench/bench_sts.rb
#   BENCH_JSON=/tmp/results.json bundle exec ruby tmp/bench/bench_sts.rb

require_relative "bench_common"
require_relative "gate_config"
include BenchCommon

print_header("STS Ruby Benchmark — ISO/NISO STS document parsing")

sts_root = ENV["STS_DIR"] || "/Users/mulgogi/src/mn/sts-ruby"
$LOAD_PATH.unshift("#{sts_root}/lib")
require "sts"

sts_files = [
  ["feature-doc-23KB",  "#{sts_root}/spec/fixtures/iso_sts/feature_doc.xml"],
  ["tbx-nisosts-101KB", "#{sts_root}/spec/fixtures/tbx-nisosts-0.2.xml"],
  ["iso-13849-1MB",
   "#{sts_root}/spec/fixtures/ISO_13849-1_2008-12_en_TBX.xml"],
  ["din-iso-1.1MB",
   "#{sts_root}/spec/fixtures/DIN_EN_ISO_13849-1_2008-12_en_TBX.xml"],
]

results = {}
sts_files.each do |label, path|
  unless File.exist?(path)
    puts "  SKIP #{label}: #{path} not found"
    next
  end
  xml = File.read(path)
  size_kb = File.size(path) / 1024.0
  results[label] = measure("STS #{label} (#{size_kb.round(0)}KB)") do
    Sts::NisoSts::Standard.from_xml(xml)
  end
end

# The informative print reads the configured gate (bench_compare is the
# enforcing layer). The old hardcoded 2.0s literal predated the
# gate_config split and mislabeled every CI run (#313, TODO.max-perf/09).
puts "\n  Gate checks:"
if results["iso-13849-1MB"]
  gate = GateConfig::GATES.dig(:sts, "iso-13849-1MB") || {}
  limit = gate[:absolute_max]
  avg = results["iso-13849-1MB"][:avg_time]
  status = avg < limit ? "PASS" : "FAIL"
  printf "  ISO-13849-1MB < %.1fs: %s (%.3fs)\n", limit, status, avg
end

write_results_json(json_output_path, results) if json_output_path
