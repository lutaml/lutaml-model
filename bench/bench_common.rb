# frozen_string_literal: true

# Shared benchmark infrastructure for lutaml-model performance testing.
# Each bench_*.rb script requires this file.
#
# Usage:
#   bundle exec ruby bench/bench_xmi.rb
#   bundle exec ruby bench/bench_niso.rb
#   bundle exec ruby bench/bench_sts.rb
#   bundle exec ruby bench/bench_mml.rb
#   bundle exec ruby bench/bench_unitsml.rb
#   bundle exec ruby bench/bench_uniword.rb

require "bundler/setup"
require "benchmark"
require "fileutils"

module BenchCommon
  ITERATIONS = (ENV["ITERATIONS"] || "3").to_i
  WARMUP_ITERATIONS = 1

  module_function

  # Measure parse time and allocations for a block
  def measure(name, iterations: ITERATIONS)
    # Warmup
    WARMUP_ITERATIONS.times { yield }

    times = []
    allocations = []
    iterations.times do
      GC.start
      GC.disable
      mem_before = ObjectSpace.count_objects[:TOTAL]
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      GC.enable
      mem_after = ObjectSpace.count_objects[:TOTAL]
      times << (t1 - t0)
      allocations << (mem_after - mem_before)
    end

    avg_time = times.sum / times.size
    min_time = times.min
    max_time = times.max
    avg_alloc = (allocations.sum / allocations.size).round
    ips = 1.0 / avg_time

    printf "  %-55s %6.3fs (min: %.3f, max: %.3f)  %9d allocs  %6.1f IPS\n",
           name, avg_time, min_time, max_time, avg_alloc, ips

    {
      name: name,
      avg_time: avg_time,
      min_time: min_time,
      max_time: max_time,
      allocations: avg_alloc,
      ips: ips
    }
  end

  # Run stackprof allocation profile and print top N methods
  def stackprof_top(name, top_n: 25, iterations: 10, &block)
    require "stackprof"

    dump_path = "/tmp/lutaml_bench_#{name}.dump"
    StackProf.run(mode: :object, out: dump_path, raw: true) do
      iterations.times(&block)
    end

    report = StackProf::Report.from_file(dump_path)
    total = report.data[:samples] || 0

    puts "\n  Stackprof Object Allocation Profile (#{name})"
    puts "  Total allocations: #{total}"
    puts "  #{'-' * 80}"
    printf "  %8s %6s  %s\n", "Allocs", "%", "Method"
    puts "  #{'-' * 80}"

    report.data[:frames]
      .sort_by { |_, v| -(v[:samples] || 0) }
      .first(top_n)
      .each do |_, v|
        samples = v[:samples] || 0
        pct = (samples.to_f / total * 100).round(1)
        printf "  %8d %5.1f%%  %s\n", samples, pct, v[:name]
      end

    { total: total, dump_path: dump_path }
  end

  # Print a summary comparison between two result sets
  def print_comparison(label, before, after)
    delta_time = ((after[:avg_time] - before[:avg_time]) / before[:avg_time] * 100).round(1)
    delta_alloc = if before[:allocations] > 0
                    ((after[:allocations] - before[:allocations]).to_f / before[:allocations] * 100).round(1)
                  else
                    "N/A"
                  end
    delta_ips = ((after[:ips] - before[:ips]) / before[:ips] * 100).round(1)
    printf "\n  %-30s %+.1f%% time  %s%% allocs  %+.1f%% IPS\n",
           label, delta_time, delta_alloc, delta_ips
  end

  def print_header(title)
    puts "=" * 90
    puts title
    puts "=" * 90
    puts "Ruby #{RUBY_VERSION} / #{RUBY_PLATFORM} / #{RUBY_RELEASE_DATE}"
    puts "Iterations: #{ITERATIONS}"
    puts
  end

  # Write benchmark results to a JSON file for later comparison.
  # Each entry keyed by fixture label.
  def write_results_json(path, results)
    require "json"
    data = results.transform_values do |r|
      {
        avg_time: r[:avg_time],
        min_time: r[:min_time],
        max_time: r[:max_time],
        allocations: r[:allocations],
        ips: r[:ips],
      }
    end
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(data) + "\n")
    puts "  Results written to #{path}"
  end

  # Load benchmark results from a JSON file.
  def load_results_json(path)
    require "json"
    JSON.parse(File.read(path), symbolize_names: true)
  end

  # JSON output path from --json-output=FILE or BENCH_JSON env var
  def json_output_path
    default = ENV["BENCH_JSON"]
    ARGV.each do |arg|
      default = $1 if arg =~ /--json-output=(.+)/
    end
    default
  end
end
