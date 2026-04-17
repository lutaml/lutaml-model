#!/usr/bin/env ruby
# frozen_string_literal: true

# Run all downstream benchmarks sequentially
#
# Usage:
#   bundle exec ruby tmp/bench/bench_all.rb
#   BENCH_JSON=/tmp/bench_current.json ITERATIONS=5 bundle exec ruby tmp/bench/bench_all.rb
#
# GHA example:
#   XMI_DIR=$GITHUB_WORKSPACE/xmi STS_DIR=$GITHUB_WORKSPACE/sts-ruby \
#     MML_DIR=$GITHUB_WORKSPACE/mml UNIWORD_DIR=$GITHUB_WORKSPACE/uniword \
#     BENCH_JSON=/tmp/bench_current.json ITERATIONS=3 \
#     bundle exec ruby tmp/bench/bench_all.rb

bench_dir = File.dirname(__FILE__)

# Targets that run from the lutaml-model bundle
local_targets = %w[xmi sts mml uniword]

# Targets that need their own bundle (different gem dependencies)
remote_targets = %w[niso unitsml]

puts "Running benchmarks from lutaml-model bundle"
puts "=" * 90

local_targets.each do |target|
  script = File.join(bench_dir, "bench_#{target}.rb")
  if File.exist?(script)
    puts
    system("bundle exec ruby #{script}")
  else
    puts "SKIP #{target}: #{script} not found"
  end
end

unless remote_targets.empty?
  puts
  puts "=" * 90
  puts "Note: The following require their own bundle (run separately):"
  remote_targets.each do |target|
    script = File.join(bench_dir, "bench_#{target}.rb")
    puts "  #{target}: #{script}" if File.exist?(script)
  end
  puts
  puts "  NISO JATS: cd $NISO_DIR && bundle exec ruby #{bench_dir}/bench_niso.rb"
  puts "  Unitsml:   cd $UNITSML_DIR && bundle exec ruby #{bench_dir}/bench_unitsml.rb"
end

puts
puts "=" * 90
puts "All local benchmarks complete."
