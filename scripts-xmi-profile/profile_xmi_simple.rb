#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple XMI Performance Profiling Script (no external dependencies)
#
# This script helps identify performance bottlenecks using only Ruby's
# standard library. Run from the xmi repository.
#
# Usage:
#   XMI_SAMPLE_FILE=path/to/sample.xmi ruby profile_xmi_simple.rb

require "bundler/setup"
require "benchmark"
require "objspace"

begin
  require "xmi"
rescue LoadError
  puts "ERROR: xmi gem not found. Please run this script from the xmi repository."
  exit 1
end

SAMPLE_FILE = ENV.fetch("XMI_SAMPLE_FILE", nil)

unless SAMPLE_FILE && File.exist?(SAMPLE_FILE)
  puts <<~MSG
    ERROR: No sample XMI file specified.

    Please set the XMI_SAMPLE_FILE environment variable:
      XMI_SAMPLE_FILE=path/to/sample.xmi ruby profile_xmi_simple.rb
  MSG
  exit 1
end

puts "=" * 80
puts "XMI Simple Performance Profile"
puts "=" * 80

xmi_content = File.read(SAMPLE_FILE)
puts "File: #{SAMPLE_FILE} (#{File.size(SAMPLE_FILE)} bytes)"
puts

# Method call tracing
puts "-" * 40
puts "Method Call Tracing (top 30 by calls)"
puts "-" * 40

call_counts = Hash.new(0)
Hash.new(0.0)

trace = TracePoint.new(:call, :c_call) do |tp|
  # Only trace lutaml-model code
  next unless tp.path&.include?("lutaml")

  method_name = "#{tp.defined_class}##{tp.method_id}"
  call_counts[method_name] += 1
end

# Enable tracing and run
GC.start
trace.enable
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

begin
  Xmi::EaRoot.from_xml(xmi_content)
rescue StandardError => e
  puts "Parse error (continuing with profile): #{e.message}"
end

finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
trace.disable

puts "Total parse time: #{(finish - start).round(3)}s"
puts

# Sort by call count
sorted_by_calls = call_counts.sort_by { |_, count| -count }.first(30)

puts "By call count:"
sorted_by_calls.each do |method, count|
  # Truncate long method names
  display_method = method.length > 70 ? "...#{method[-67..]}" : method
  puts "  #{count.to_s.reverse.gsub(/(\d{3})(?=\d)/,
                                    '\\1,').reverse.rjust(12)}: #{display_method}"
end
puts

# Look for potential issues
puts "-" * 40
puts "Potential Issues"
puts "-" * 40

# Check for methods called excessively
excessive_threshold = 10_000
excessive = call_counts.select { |_, count| count > excessive_threshold }
if excessive.any?
  puts "Methods called more than #{excessive_threshold} times:"
  excessive.sort_by { |_, c| -c }.each do |method, count|
    puts "  #{count.to_s.reverse.gsub(/(\d{3})(?=\d)/,
                                      '\\1,').reverse}: #{method}"
  end
else
  puts "No methods called more than #{excessive_threshold} times"
end
puts

# Check for duplicate detection in mapping
duplicate_checks = call_counts.select do |m, _|
  m.include?("eql?") || m.include?("==")
end
if duplicate_checks.any?
  puts "Duplicate detection calls:"
  duplicate_checks.sort_by { |_, c| -c }.each do |method, count|
    puts "  #{count}: #{method}"
  end
end
puts

# Memory analysis
puts "-" * 40
puts "Memory Analysis"
puts "-" * 40

GC.start
before = ObjectSpace.count_objects

begin
  Xmi::EaRoot.from_xml(xmi_content)
rescue StandardError => e
  puts "Parse error (continuing): #{e.message}"
end

GC.start
after = ObjectSpace.count_objects

puts "Object count changes:"
%i[T_OBJECT T_ARRAY T_HASH T_STRING T_DATA T_SYMBOL].each do |type|
  diff = (after[type] || 0) - (before[type] || 0)
  puts "  #{type}: #{'+' if diff >= 0}#{diff}"
end
puts

# Transformation registry analysis
puts "-" * 40
puts "Transformation Registry Analysis"
puts "-" * 40

if defined?(Lutaml::Model::TransformationRegistry)
  registry = Lutaml::Model::TransformationRegistry.instance
  puts "Registered transformations: #{registry.send(:transformations)&.size || 'N/A'}"

  # Try to get cache stats if available
  if registry.respond_to?(:cache_stats)
    puts "Cache stats: #{registry.cache_stats}"
  end
end
puts

# Check for mapping accumulation
puts "-" * 40
puts "Mapping Accumulation Check"
puts "-" * 40

# Look at all loaded classes that include Lutaml::Model::Serialize
lutaml_classes = ObjectSpace.each_object(Class).select do |klass|
  klass.include?(Lutaml::Model::Serialize)
rescue StandardError
  false
end

puts "Lutaml::Model classes loaded: #{lutaml_classes.size}"

# Check for classes with many mappings
classes_with_many_mappings = lutaml_classes.select do |klass|
  mappings = begin
    klass.xml_mapping&.mappings
  rescue StandardError
    []
  end
  mappings.size > 20
end

if classes_with_many_mappings.any?
  puts "Classes with >20 mappings:"
  classes_with_many_mappings.each do |klass|
    mappings = begin
      klass.xml_mapping&.mappings
    rescue StandardError
      []
    end
    puts "  #{klass}: #{mappings.size} mappings"
  end
else
  puts "No classes with excessive mappings (>20)"
end
puts

# Summary
puts "=" * 80
puts "Summary"
puts "=" * 80
puts "Total method calls traced: #{call_counts.values.sum}"
puts "Unique methods called: #{call_counts.size}"
puts
puts "To share this profile with the lutaml-model team:"
puts "  ruby profile_xmi_simple.rb > profile_output.txt 2>&1"
puts
puts "For more detailed profiling, install stackprof:"
puts "  gem install stackprof"
puts "  Then use profile_xmi.rb"
