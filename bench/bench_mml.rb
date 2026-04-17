#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: Plurimath MML (MathML parsing)
# Gate: parse time < 1.5s for complex3-567KB
#
# Usage:
#   MML_DIR=/path/to/mml ITERATIONS=5 bundle exec ruby tmp/bench/bench_mml.rb
#   BENCH_JSON=/tmp/results.json bundle exec ruby tmp/bench/bench_mml.rb

require_relative "bench_common"
include BenchCommon

print_header("Plurimath MML Benchmark — MathML parsing")

mml_root = ENV["MML_DIR"] || "/Users/mulgogi/src/plurimath/mml"
$LOAD_PATH.unshift("#{mml_root}/lib")
require "mml"

mml_files = [
  ["simple-1KB",    "#{mml_root}/spec/fixtures/mml2-testsuite/testsuite/Presentation/TokenElements/mi/mi.xml"],
  ["complex1-46KB", "#{mml_root}/spec/fixtures/mml2-testsuite/testsuite/TortureTests/Complexity/complex1.xml"],
  ["complex4-50KB", "#{mml_root}/spec/fixtures/mml2-testsuite/testsuite/TortureTests/Complexity/complex4.xml"],
  ["size1000-245KB", "#{mml_root}/spec/fixtures/mml2-testsuite/testsuite/TortureTests/Size/1000.xml"],
  ["complex3-567KB", "#{mml_root}/spec/fixtures/mml2-testsuite/testsuite/TortureTests/Complexity/complex3.xml"],
]

results = {}
mml_files.each do |label, path|
  unless File.exist?(path)
    puts "  SKIP #{label}: #{path} not found"
    next
  end
  xml = File.read(path)
  size_kb = File.size(path) / 1024.0
  results[label] = measure("MML #{label} (#{size_kb.round(0)}KB)") do
    Mml.parse(xml)
  end
end

puts "\n  Gate checks:"
if results["complex3-567KB"]
  status = results["complex3-567KB"][:avg_time] < 1.5 ? "PASS" : "FAIL"
  printf "  complex3-567KB < 1.5s: %s (%.3fs)\n", status, results["complex3-567KB"][:avg_time]
end

write_results_json(json_output_path, results) if json_output_path
