#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: Uniword (OOXML/DOCX document parsing)
# Gate: parse time < 30s for ISO-690 (4.8MB document.xml)
#
# Usage:
#   UNIWORD_DIR=/path/to/uniword ITERATIONS=5 bundle exec ruby tmp/bench/bench_uniword.rb
#   BENCH_JSON=/tmp/results.json bundle exec ruby tmp/bench/bench_uniword.rb

require_relative "bench_common"
include BenchCommon

print_header("Uniword Benchmark — OOXML/DOCX document parsing")

uniword_root = ENV["UNIWORD_DIR"] || "/Users/mulgogi/src/mn/uniword"
$LOAD_PATH.unshift("#{uniword_root}/lib")
require "uniword"
require "zip"

iso_file = "#{uniword_root}/spec/fixtures/uniword-private/fixtures/iso/ISO_690_2021-Word_document(en).docx"

unless File.exist?(iso_file)
  puts "  ISO 690 fixture not found: #{iso_file}"
  puts "  Ensure uniword-private submodule is initialized."
  exit 1
end

# Extract document.xml from DOCX
xml_content = nil
Zip::File.open(iso_file) do |zip|
  entry = zip.find_entry("word/document.xml")
  xml_content = entry.get_input_stream.read if entry
end

file_size_kb = File.size(iso_file) / 1024.0
xml_size_kb = xml_content.bytesize / 1024.0
puts "  File: #{File.basename(iso_file)} (#{file_size_kb.round(0)}KB)"
puts "  document.xml: #{xml_size_kb.round(0)}KB"
puts

results = {}
results[:iso690] = measure("Uniword ISO 690 (#{xml_size_kb.round(0)}KB)") do
  Uniword::Wordprocessingml::DocumentRoot.from_xml(xml_content)
end

# Also test with a simpler document if available
demo_file = "#{uniword_root}/examples/demo_formal_integral_roundtrip_spec.docx"
if File.exist?(demo_file)
  demo_xml = nil
  Zip::File.open(demo_file) do |zip|
    entry = zip.find_entry("word/document.xml")
    demo_xml = entry.get_input_stream.read if entry
  end
  if demo_xml
    demo_size_kb = demo_xml.bytesize / 1024.0
    results[:demo] = measure("Uniword demo_formal (#{demo_size_kb.round(0)}KB)") do
      Uniword::Wordprocessingml::DocumentRoot.from_xml(demo_xml)
    end
  end
end

puts "\n  Gate checks:"
if results[:iso690]
  status = results[:iso690][:avg_time] < 30.0 ? "PASS" : "FAIL"
  printf "  ISO-690 < 30s: %s (%.3fs)\n", status, results[:iso690][:avg_time]
end

write_results_json(json_output_path, results) if json_output_path
