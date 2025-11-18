# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "fileutils"

module PerformanceHelpers
  module Base
  end

  module Current
  end

  class << self
    def load_into_namespace(module_obj, file_path)
      content = File.read(file_path)
      module_obj.module_eval(content, file_path)
    end

    def ruby_exec(cmd, env: {})
      Open3.capture3(env, cmd)
    end

    def current_branch
      stdout, = ruby_exec("git rev-parse --abbrev-ref HEAD")
      stdout.strip
    end

    # Clone base branch into a temp dir and return its path
    def clone_base_repo(base, performance_dir, script)
      puts "Cloning base #{base}..."
      safe_ref = base.gsub(/[^0-9A-Za-z._-]/, "-")
      clone_dir = File.join(performance_dir, "base-#{safe_ref}")
      FileUtils.rm_rf(clone_dir)

      repo_url, = ruby_exec("git config --get remote.origin.url")
      repo_url = repo_url.strip

      stdout, stderr, status = ruby_exec("git clone --branch #{safe_ref} --single-branch #{repo_url} #{clone_dir}")
      raise "git clone failed: #{stderr}\n#{stdout}" unless status.success?

      Dir.chdir(clone_dir) do
        stdout, stderr, status = ruby_exec("bundle install --quiet")
        raise "bundle install failed: #{stderr}\n#{stdout}" unless status.success?

        bench_copy_dir = File.join(clone_dir, "tmp", "performance")
        FileUtils.mkdir_p(bench_copy_dir)
        bench_copy = File.join(bench_copy_dir, "benchmark_runner.rb")
        File.write(bench_copy, File.read(script))
        load_into_namespace(Base, bench_copy)
      end
    end

    def run_benchmarks(base_runner, current_runner, threshold, all_base,
all_current)
      base_results = base_runner.run_benchmarks
      curr_results = current_runner.run_benchmarks

      all_base.merge!(base_results)
      all_current.merge!(curr_results)

      curr_results.each do |label, result|
        print_realtime_comparison(label, result, base_results[label], threshold)
      end
    end

    def compare_metrics(label, curr, base, threshold)
      base_ips = base.fetch(:lower)
      curr_ips = curr.fetch(:upper)
      change = (curr_ips - base_ips) / base_ips.to_f

      {
        label: label,
        base_ips: base_ips,
        curr_ips: curr_ips,
        change: change,
        regressed: change < -threshold,
      }
    end

    def summary_report(current_results, base_results, base, run_time, threshold)
      summary = {
        run_time: run_time,
        threshold: threshold,
        branch: current_branch,
        base: base,
        regressions: [],
      }

      current_results.each do |label, metrics|
        cmp = compare_metrics(label, metrics, base_results[label], threshold)
        next unless cmp[:regressed]

        summary[:regressions] << {
          label: label,
          base_ips: cmp[:base_ips],
          curr_ips: cmp[:curr_ips],
          delta_fraction: cmp[:change],
        }
      end

      log_regressions(summary[:regressions], threshold)
      summary
    end

    def log_regressions(regressions, threshold)
      return if regressions.empty?

      puts "\nDetected regressions (< -#{(threshold * 100).round(2)}% IPS):"
      regressions.each do |regression|
        delta = regression[:delta_fraction]
        base_ips = regression[:base_ips]
        curr_ips = regression[:curr_ips]

        delta_str = delta ? format("%+0.2f%%", delta * 100) : "N/A"
        base_str = base_ips ? format("%.2f", base_ips) : "N/A"
        curr_str = curr_ips ? format("%.2f", curr_ips) : "N/A"

        puts format("%<label>30s: %<base>s -> %<curr>s IPS (change: %<delta>s)",
                    label: regression[:label],
                    base: base_str,
                    curr: curr_str,
                    delta: delta_str)
      end
    end

    private

    def print_realtime_comparison(label, curr_metrics, base_metrics, threshold)
      curr_ips = curr_metrics[:upper]
      base_ips = base_metrics[:lower]
      return unless curr_ips && base_ips

      change = (curr_ips - base_ips) / base_ips.to_f
      status = change < -threshold ? "REGRESSED" : "OK"
      delta_str = format("%+0.2f%%", change * 100)
      base_str = format("%.2f", base_ips)
      curr_str = format("%.2f", curr_ips)

      puts format("%<label>30s: %<base>s -> %<curr>s IPS (change: %<delta>s) [%<status>s]\n\n",
                  label: label,
                  base: base_str,
                  curr: curr_str,
                  delta: delta_str,
                  status: status)
    end
  end
end
