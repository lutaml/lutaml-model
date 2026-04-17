#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: NISO JATS (Journal Article parsing)
# Gate: parse time < 0.40s for pnas-152KB
#
# Usage:
#   NISO_DIR=/path/to/niso-jats ITERATIONS=5 bundle exec ruby bench/bench_niso.rb
#   BENCH_JSON=/tmp/results.json bundle exec ruby bench/bench_niso.rb
#
# NOTE: Must run from the niso-jats bundle:
#   cd $NISO_DIR && bundle exec ruby /path/to/lutaml-model/bench/bench_niso.rb

lutaml_model_root = ENV["LUTAML_MODEL_DIR"] || "/Users/mulgogi/src/lutaml/lutaml-model"
require "#{lutaml_model_root}/bench/bench_common"
include BenchCommon

print_header("NISO JATS Benchmark — Journal Article parsing")

niso_root = ENV["NISO_DIR"] || "/Users/mulgogi/src/mn/niso-jats"
$LOAD_PATH.unshift("#{niso_root}/lib")
require "niso/jats"

niso_files = [
  ["metrology-4KB",  "#{niso_root}/spec/fixtures/metrologia/metv9i4p155.xml"],
  ["bmj-49KB",       "#{niso_root}/spec/fixtures/bmj_sample.xml"],
  ["elementa-115KB",
   "#{niso_root}/spec/fixtures/niso-jats/publishing/1.1d3/Smallsamples/journal.elementa.000012.xml"],
  ["elementa-125KB",
   "#{niso_root}/spec/fixtures/niso-jats/publishing/1.1d3/Smallsamples/journal.elementa.000017.xml"],
  ["pnas-152KB", "#{niso_root}/spec/fixtures/pnas_sample.xml"],
]

results = {}
niso_files.each do |label, path|
  unless File.exist?(path)
    puts "  SKIP #{label}: #{path} not found"
    next
  end
  xml = File.read(path)
  size_kb = File.size(path) / 1024.0
  results[label] = measure("JATS #{label} (#{size_kb.round(0)}KB)") do
    Niso::Jats::Article.from_xml(xml)
  end
end

puts "\n  Gate checks:"
if results["pnas-152KB"]
  status = results["pnas-152KB"][:avg_time] < 0.25 ? "PASS" : "FAIL"
  printf "  pnas-152KB < 0.25s: %s (%.3fs)\n", status,
         results["pnas-152KB"][:avg_time]
end

write_results_json(json_output_path, results) if json_output_path
