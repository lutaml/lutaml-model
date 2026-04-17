# frozen_string_literal: true

require_relative "performance_comparator"

BENCH_DIR = File.expand_path("../../bench", __dir__)

def run_bench(script, *extra_args)
  cmd = ["bundle", "exec", "ruby", script] + extra_args
  success = system(*cmd)
  raise "Benchmark failed: #{script}" unless success
end

desc "Run performance benchmarks"
namespace :performance do
  desc "compare performance of current branch against base branch (default: main)"
  task :compare do
    PerformanceComparator.new.run
  end

  # --- Downstream benchmark tasks (GHA-ready) ---
  #
  # Each downstream project path is configurable via environment variables:
  #   XMI_DIR, STS_DIR, MML_DIR, NISO_DIR, UNITSML_DIR, UNIWORD_DIR
  #
  # Example for GHA:
  #   XMI_DIR=/path/to/checkout/xmi ITERATIONS=3 bundle exec rake performance:xmi
  #
  # JSON output for gate comparison:
  #   BENCH_JSON=/tmp/results.json bundle exec rake performance:xmi
  #
  # All accept ITERATIONS env var (default: 3).

  desc "Run XMI downstream benchmark"
  task :xmi do
    run_bench("#{BENCH_DIR}/bench_xmi.rb")
  end

  desc "Run STS Ruby downstream benchmark"
  task :sts do
    run_bench("#{BENCH_DIR}/bench_sts.rb")
  end

  desc "Run Plurimath MML downstream benchmark"
  task :mml do
    run_bench("#{BENCH_DIR}/bench_mml.rb")
  end

  desc "Run Uniword downstream benchmark"
  task :uniword do
    run_bench("#{BENCH_DIR}/bench_uniword.rb")
  end

  desc "Run all local downstream benchmarks (xmi, sts, mml, uniword)"
  task all_local: %i[xmi sts mml uniword]

  desc "Run NISO JATS downstream benchmark"
  task :niso do
    run_bench("#{BENCH_DIR}/bench_niso.rb")
  end

  desc "Run Unitsml downstream benchmark"
  task :unitsml do
    run_bench("#{BENCH_DIR}/bench_unitsml.rb")
  end

  # --- Gate comparison ---

  desc "Compare downstream benchmark JSON results (gate enforcement)"
  task :downstream_gates, [:base_json, :current_json] do |_t, args|
    base = args[:base_json] || ENV["BENCH_BASE_JSON"] || "/tmp/bench_base.json"
    current = args[:current_json] || ENV["BENCH_CURRENT_JSON"] || "/tmp/bench_current.json"
    success = system("ruby", "#{BENCH_DIR}/bench_compare.rb", base, current)
    raise "Gate comparison failed" unless success
  end
end
