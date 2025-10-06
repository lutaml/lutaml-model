# frozen_string_literal: true

require_relative "performance_helpers"

class PerformanceComparator
  REPO_ROOT = File.expand_path(File.join(__dir__, "..", ".."))
  DEFAULT_RUN_TIME = 20 # seconds
  DEFAULT_THRESHOLD = 0.05 # 5%
  DEFAULT_BASE = "main"
  TMP_PERF_DIR = File.join(REPO_ROOT, "tmp", "performance")
  BENCH_SCRIPT = File.join(TMP_PERF_DIR, "bench_runner.rb")

  BENCHMARK_MATRIX = {
    xml: %i[nokogiri ox oga],
    json: %i[standard_json multi_json oj],
    yaml: %i[standard_yaml],
    toml: %i[toml_rb tomlib],
  }.freeze

  DIRECTIONS = %i[from to].freeze

  def run
    setup_environment
    run_benchmarks_comparison
  ensure
    cleanup
  end

  private

  def setup_environment
    Dir.chdir(REPO_ROOT)
    FileUtils.mkdir_p(TMP_PERF_DIR)
    FileUtils.cp(File.join(REPO_ROOT, "lib", "tasks", "bench_runner.rb"), BENCH_SCRIPT)

    PerformanceHelpers.load_into_namespace(PerformanceHelpers::Current, BENCH_SCRIPT)
    PerformanceHelpers.clone_base_repo(DEFAULT_BASE, TMP_PERF_DIR, BENCH_SCRIPT)
  end

  def run_benchmarks_comparison
    all_current = {}
    all_base = {}

    BENCHMARK_MATRIX.each do |format_sym, adapters|
      adapters.each do |adapter_sym|
        puts "\n== Running #{format_sym}:#{adapter_sym} (base then current) =="
        run_format_benchmarks(format_sym, adapter_sym, all_base, all_current)
      end
    end

    summary = PerformanceHelpers.summary_report(
      all_current,
      all_base,
      DEFAULT_BASE,
      DEFAULT_RUN_TIME,
      DEFAULT_THRESHOLD,
    )

    handle_results(summary)
  end

  def run_format_benchmarks(format_sym, adapter_sym, all_base, all_current)
    DIRECTIONS.each do |direction|
      base_runner = PerformanceHelpers::Base::BenchRunner.new(
        run_time: DEFAULT_RUN_TIME,
        format: format_sym,
        adapter: adapter_sym,
        direction: direction,
      )

      current_runner = PerformanceHelpers::Current::BenchRunner.new(
        run_time: DEFAULT_RUN_TIME,
        format: format_sym,
        adapter: adapter_sym,
        direction: direction,
      )

      PerformanceHelpers.run_benchmarks(
        base_runner,
        current_runner,
        DEFAULT_THRESHOLD,
        all_base,
        all_current,
      )
    end
  end

  def handle_results(summary)
    return unless summary[:regressions].any?

    warn "Performance regressions detected!"
    exit(1)
  end

  def cleanup
    FileUtils.rm_rf(TMP_PERF_DIR)
  end
end
