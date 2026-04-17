#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: Unitsml Ruby (UnitsML parsing)
# Gate: 1000 parse operations < 2.0s total
#
# Usage:
#   UNITSML_DIR=/path/to/unitsml-ruby ITERATIONS=5 bundle exec ruby tmp/bench/bench_unitsml.rb
#   BENCH_JSON=/tmp/results.json bundle exec ruby tmp/bench/bench_unitsml.rb

require_relative "bench_common"
include BenchCommon

print_header("Unitsml Ruby Benchmark — UnitsML expression parsing")

unitsml_root = ENV["UNITSML_DIR"] || "/Users/mulgogi/src/unitsml/unitsml-ruby"
$LOAD_PATH.unshift("#{unitsml_root}/lib")
require "unitsml"

# Unitsml parses string expressions like "unitsml(mm*s^-2)"
expressions = [
  "unitsml(mm*s^-2)",
  "unitsml(um)",
  "unitsml(degK)",
  "unitsml(prime)",
  "unitsml(kg*m^2*s^-2)",
  "unitsml(m*s^-1)",
  "unitsml(A)",
  "unitsml(m^2)",
]

puts "  Parsing #{expressions.size} expressions x 100 times..."
results = {}
results["800-expressions"] = measure("Unitsml 800 expressions") do
  100.times do
    expressions.each { |exp| Unitsml::Parser.new(exp).parse }
  end
end

puts "\n  Note: Unitsml uses parslet for parsing, not heavy lutaml-model XML deserialization."
puts "  Performance gains here will come from Unitsml::Unit.from_xml and symbol rendering."

write_results_json(json_output_path, results) if json_output_path
