# frozen_string_literal: true

require_relative "performance_helpers"

REPO_ROOT = File.expand_path(File.join(__dir__, "..", ".."))
DEFAULT_RUN_TIME = 20 # seconds
DEFAULT_THRESHOLD = 0.05 # 5%
DEFAULT_BASE = "main"
TMP_PERF_DIR = File.join(REPO_ROOT, "tmp", "performance")
BENCH_SCRIPT = File.join(TMP_PERF_DIR, "bench_runner.rb")

desc "Run performance benchmarks"
namespace :performance do
  desc "compare performance of current branch against base branch (default: main)"
  task :compare do
    # Change to repo root
    Dir.chdir(REPO_ROOT)

    # Copy benchmark script to stable tmp location
    FileUtils.mkdir_p(TMP_PERF_DIR)
    ruby_exec("cp #{File.join(REPO_ROOT, 'lib', 'tasks', 'bench_runner.rb')} #{BENCH_SCRIPT}")

    load_into_namespace(Current, BENCH_SCRIPT)

    matrix = { xml: %i[nokogiri ox oga], json: %i[standard_json multi_json oj],
               yaml: %i[standard_yaml], toml: %i[toml_rb tomlib] }
    directions = %i[from to]

    clone_base_repo(DEFAULT_BASE, TMP_PERF_DIR, BENCH_SCRIPT)

    begin
      all_current = {}
      all_base = {}

      matrix.each do |format_sym, adapters|
        adapters.each do |adapter_sym|
          puts "\n== Running #{format_sym}:#{adapter_sym} (base then current) =="
          directions.each do |direction|
            base_results = Base::BenchRunner.new(run_time: DEFAULT_RUN_TIME, format: format_sym, adapter: adapter_sym, direction: direction).run_benchmarks
            curr_results = Current::BenchRunner.new(run_time: DEFAULT_RUN_TIME, format: format_sym, adapter: adapter_sym, direction: direction).run_benchmarks

            all_base.merge!(base_results)
            all_current.merge!(curr_results)

            curr_results.each do |label, result|
              print_realtime_comparison(label, result, base_results[label], DEFAULT_THRESHOLD)
            end
          end
        end
      end

      summary = summary_report(all_current, all_base, DEFAULT_BASE, DEFAULT_RUN_TIME, DEFAULT_THRESHOLD)

      exit(1) if !summary[:regressions].empty?
    ensure
      FileUtils.rm_rf(TMP_PERF_DIR)
    end
  end
end
