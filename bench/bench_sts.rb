#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: STS Ruby (ISO/NISO STS document parsing)
# Gate: parse time < 2.0s for ISO-13849-1MB
#
# Usage:
#   STS_DIR=/path/to/sts-ruby ITERATIONS=5 bundle exec ruby tmp/bench/bench_sts.rb
#   BENCH_JSON=/tmp/results.json bundle exec ruby tmp/bench/bench_sts.rb

require_relative "bench_common"
include BenchCommon

print_header("STS Ruby Benchmark — ISO/NISO STS document parsing")

sts_root = ENV["STS_DIR"] || "/Users/mulgogi/src/mn/sts-ruby"
$LOAD_PATH.unshift("#{sts_root}/lib")
require "sts"

sts_files = [
  ["feature-doc-23KB",  "#{sts_root}/spec/fixtures/iso_sts/feature_doc.xml"],
  ["tbx-nisosts-101KB", "#{sts_root}/spec/fixtures/tbx-nisosts-0.2.xml"],
  ["iso-13849-1MB",     "#{sts_root}/spec/fixtures/ISO_13849-1_2008-12_en_TBX.xml"],
  ["din-iso-1.1MB",     "#{sts_root}/spec/fixtures/DIN_EN_ISO_13849-1_2008-12_en_TBX.xml"],
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

puts "\n  Gate checks:"
if results["iso-13849-1MB"]
  status = results["iso-13849-1MB"][:avg_time] < 2.0 ? "PASS" : "FAIL"
  printf "  ISO-13849-1MB < 2.0s: %s (%.3fs)\n", status, results["iso-13849-1MB"][:avg_time]
end

write_results_json(json_output_path, results) if json_output_path
