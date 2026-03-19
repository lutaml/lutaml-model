#!/usr/bin/env ruby
# frozen_string_literal: true

# XMI Performance Profiling Script
#
# This script helps identify performance bottlenecks in lutaml-model when used
# with complex XML models like those in the xmi gem.
#
# Usage:
#   1. Copy this script to the xmi gem repository
#   2. Install stackprof: gem install stackprof
#   3. Run: ruby profile_xmi.rb
#
# Requirements:
#   - stackprof gem
#   - A sample XMI file to parse

require "bundler/setup"
require "stackprof" if Gem.loaded_specs.key?("stackprof")
require "benchmark"
require "json"

# Try to load the xmi gem
begin
  require "xmi"
rescue LoadError
  puts "ERROR: xmi gem not found. Please run this script from the xmi repository."
  exit 1
end

# Try to load a sample XMI file
SAMPLE_FILE = ENV.fetch("XMI_SAMPLE_FILE", nil)

unless SAMPLE_FILE && File.exist?(SAMPLE_FILE)
  puts <<~MSG
    ERROR: No sample XMI file specified.

    Please set the XMI_SAMPLE_FILE environment variable:
      XMI_SAMPLE_FILE=path/to/sample.xmi ruby profile_xmi.rb

    Or find sample files in your repository and use one of them.
  MSG
  exit 1
end

puts "=" * 80
puts "XMI Performance Profiling"
puts "=" * 80
puts "Sample file: #{SAMPLE_FILE}"
puts "File size: #{File.size(SAMPLE_FILE)} bytes"
puts

# Read the sample file
xmi_content = File.read(SAMPLE_FILE)

# Warm-up runs (to let Ruby optimize)
puts "Running warm-up..."
3.times do
  Xmi::EaRoot.from_xml(xmi_content)
rescue StandardError
  nil
end
puts

# Benchmark raw parsing
puts "-" * 40
puts "Timing Benchmark"
puts "-" * 40

times = []
5.times do |i|
  puts "Run #{i + 1}..."
  time = Benchmark.realtime do
    Xmi::EaRoot.from_xml(xmi_content)
  rescue StandardError
    nil
  end
  times << time
  puts "  #{time.round(3)}s"
end

avg_time = times.sum / times.size
puts
puts "Average time: #{avg_time.round(3)}s"
puts "Min time: #{times.min.round(3)}s"
puts "Max time: #{times.max.round(3)}s"
puts

# Memory profiling
puts "-" * 40
puts "Memory Profile"
puts "-" * 40

require "objspace"
GC.start
before_mem = ObjectSpace.memsize_of_all
before_objects = ObjectSpace.count_objects

begin
  Xmi::EaRoot.from_xml(xmi_content)
rescue StandardError
  nil
end

GC.start
after_mem = ObjectSpace.memsize_of_all
after_objects = ObjectSpace.count_objects

mem_diff = after_mem - before_mem
puts "Memory change: #{(mem_diff / 1024.0 / 1024.0).round(2)} MB"

# Object count changes
interesting_types = %i[T_OBJECT T_ARRAY T_HASH T_STRING T_DATA]
puts "Object count changes:"
interesting_types.each do |type|
  before_count = before_objects[type] || 0
  after_count = after_objects[type] || 0
  diff = after_count - before_count
  puts "  #{type}: #{before_count} -> #{after_count} (#{'+' if diff >= 0}#{diff})"
end
puts

# StackProf profiling (if available)
puts "-" * 40
if defined?(StackProf)
  puts "StackProf CPU Profiling"
  puts "-" * 40

  profile_file = "/tmp/xmi_profile.dump"

  StackProf.run(mode: :cpu, out: profile_file, raw: true) do
    3.times do
      Xmi::EaRoot.from_xml(xmi_content)
    rescue StandardError
      nil
    end
  end

  puts "Profile saved to: #{profile_file}"
  puts
  puts "Top 20 methods by total time:"
  puts

  result = StackProf::Report.new(path: profile_file)
  result.print_text(sort_by_total: true, limit: 20)

  puts
  puts "To view flame graph:"
  puts "  stackprof --flamegraph #{profile_file} > flamegraph.html"
  puts "  stackprof --method='ClassName#method' #{profile_file}"
  puts

  # Check for specific lutaml-model methods
  puts "-" * 40
  puts "Lutaml::Model specific hotspots"
  puts "-" * 40

  # Read the raw profile data
  profile_data = Marshal.load(File.binread(profile_file))

  lutaml_methods = profile_data[:frames].select do |_addr, frame|
    frame[:name]&.include?("Lutaml") || frame[:file]&.include?("lutaml")
  end

  if lutaml_methods.any?
    sorted = lutaml_methods.sort_by { |_, f| -(f[:total_samples] || 0) }
    puts "Top Lutaml methods by samples:"
    sorted.first(15).each_value do |frame|
      samples = frame[:total_samples] || 0
      name = frame[:name] || "unknown"
      file = frame[:file] || "unknown"
      line = frame[:line] || 0
      puts "  #{samples.to_s.rjust(5)} samples: #{name}"
      puts "           #{File.basename(file)}:#{line}"
    end
  else
    puts "No lutaml-specific methods found in profile"
  end
else
  puts "StackProf not available"
  puts "-" * 40
  puts "Install stackprof for detailed CPU profiling:"
  puts "  gem install stackprof"
  puts
  puts "Or add to Gemfile:"
  puts "  gem 'stackprof', require: false"
end

puts
puts "=" * 80
puts "Profiling complete"
puts "=" * 80
