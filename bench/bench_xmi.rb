#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: XMI (Sparx EA XMI parsing)
# Gate: parse time < 0.15s for ea251, < 3.5s for full-242
#
# Usage:
#   XMI_DIR=/path/to/xmi ITERATIONS=5 bundle exec ruby tmp/bench/bench_xmi.rb
#   BENCH_JSON=/tmp/results.json bundle exec ruby tmp/bench/bench_xmi.rb

require_relative "bench_common"
include BenchCommon

print_header("XMI Benchmark — Sparx EANode parsing")

xmi_root = ENV["XMI_DIR"] || "/Users/mulgogi/src/lutaml/xmi"
$LOAD_PATH.unshift("#{xmi_root}/lib")
require "xmi"

xmi_dir = "#{xmi_root}/spec/fixtures"
xmi_files = {
  ea251:  "#{xmi_dir}/ea-xmi-2.5.1.xmi",                  # 93KB
  medium: "#{xmi_dir}/xmi-v2-4-2-default.xmi",             # 310KB
  citygml: "#{xmi_dir}/xmi-v2-4-2-default-with-citygml.xmi", # 514KB
  large:  "#{xmi_dir}/full-242.xmi",                        # 3.5MB
}

results = {}
xmi_files.each do |label, path|
  unless File.exist?(path)
    puts "  SKIP #{label}: #{path} not found"
    next
  end
  xml = File.read(path)
  size_kb = File.size(path) / 1024.0
  results[label] = measure("XMI #{label} (#{size_kb.round(0)}KB)") do
    Xmi::Sparx::SparxRoot.parse_xml(xml)
  end
end

puts "\n  Gate checks:"
if results[:ea251]
  status = results[:ea251][:avg_time] < 0.15 ? "PASS" : "FAIL"
  printf "  ea251 < 0.15s: %s (%.3fs)\n", status, results[:ea251][:avg_time]
end
if results[:large]
  status = results[:large][:avg_time] < 3.5 ? "PASS" : "FAIL"
  printf "  full-242 < 3.5s: %s (%.3fs)\n", status, results[:large][:avg_time]
end

write_results_json(json_output_path, results) if json_output_path
