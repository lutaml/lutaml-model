# frozen_string_literal: true

require_relative "performance_helpers"

REPO_ROOT = File.expand_path(File.join(__dir__, "..", ".."))
DEFAULT_RUNS = 30
DEFAULT_THRESHOLD = 0.25 # 25%
DEFAULT_BASELINE = "main"
TMP_PERF_DIR = File.join(REPO_ROOT, "tmp", "performance")
BENCH_SCRIPT = File.join(TMP_PERF_DIR, "bench_runner.rb")

desc "Run performance benchmarks"
namespace :performance do
  desc "compare performance of current branch against baseline"
  task :compare do
    # Change to repo root
    Dir.chdir(REPO_ROOT)

    # Copy benchmark script to stable tmp location
    FileUtils.mkdir_p(TMP_PERF_DIR)
    ruby_exec("cp #{File.join(REPO_ROOT, 'lib', 'tasks', 'bench_runner.rb')} #{BENCH_SCRIPT}")

    matrix = { xml: %i[nokogiri ox oga], json: %i[standard_json multi_json oj],
               yaml: %i[standard_yaml], toml: %i[toml_rb tomlib] }

    baseline_dir = clone_baseline_repo(DEFAULT_BASELINE, TMP_PERF_DIR)

    begin
      all_current = {}
      all_baseline = {}

      matrix.each do |format_sym, adapters|
        adapters.each do |adapter_sym|
          puts "\n== Running #{format_sym}:#{adapter_sym} (baseline then current) =="

          curr_results = run_filtered_local(BENCH_SCRIPT, DEFAULT_RUNS, format_sym, adapter_sym)

          base_results = run_in_repo(BENCH_SCRIPT, DEFAULT_RUNS, baseline_dir,
                                     { "FILTER_FORMAT" => format_sym.to_s, "FILTER_ADAPTER" => adapter_sym.to_s })

          all_baseline.merge!(base_results)
          all_current.merge!(curr_results)

          curr_results.each do |label, result|
            print_realtime_comparison(label, result, base_results[label], DEFAULT_THRESHOLD)
          end
        end
      end

      summary = summary_report(all_current, all_baseline, DEFAULT_BASELINE, DEFAULT_RUNS, DEFAULT_THRESHOLD)

      exit(1) if !summary[:regressions].empty? || !summary[:failures].empty?
    ensure
      FileUtils.rm_rf(BENCH_SCRIPT)
      remove_baseline_repo(baseline_dir)
    end
  end
end
