# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "fileutils"

def ruby_exec(cmd, env: {})
  stdout, stderr, status = Open3.capture3(env, cmd)
  [stdout, stderr, status]
end

def bundle_exec_ruby(script_path, env: {})
  ruby_exec("bundle exec ruby #{script_path}", env: env)
end

def current_branch
  out, _err, _st = ruby_exec("git rev-parse --abbrev-ref HEAD")
  out.strip
end

def sanitize_filename(name)
  name.gsub(/[^0-9A-Za-z._-]/, "-")
end

# Clone baseline branch into a temp dir and return its path
def clone_baseline_repo(base, performance_dir)
  puts "Cloning baseline #{base}...\n"
  safe_ref = sanitize_filename(base)
  clone_dir = File.join(performance_dir, "baseline-#{safe_ref}")
  FileUtils.rm_rf(clone_dir)
  repo_url = `git config --get remote.origin.url`.strip
  stdout, stderr, st = ruby_exec("git clone --branch #{base} --single-branch #{repo_url} #{clone_dir}")
  raise "git clone failed: #{stderr}\n#{stdout}" unless st.success?

  clone_dir
end

def remove_baseline_repo(clone_dir)
  FileUtils.rm_rf(clone_dir)
end

def run_in_repo(script, runs, repo_dir, extra_env = {})
  Dir.chdir(repo_dir) do
    ruby_exec("bundle install --quiet")
    bench_copy_dir = File.join(repo_dir, "tmp", "performance")
    FileUtils.mkdir_p(bench_copy_dir)
    bench_copy = File.join(bench_copy_dir, "bench_runner.rb")
    File.write(bench_copy, File.read(script))
    env = { "RUNS" => runs.to_s }.merge(extra_env)
    stdout, stderr, st = bundle_exec_ruby(bench_copy, env: env)
    raise "Benchmark failed: #{stderr}" unless st.success?

    JSON.parse(stdout)
  end
end

def run_filtered_local(script, runs, format_sym, adapter_sym)
  env = { "RUNS" => runs.to_s, "FILTER_FORMAT" => format_sym.to_s, "FILTER_ADAPTER" => adapter_sym.to_s }
  stdout, stderr, st = bundle_exec_ruby(script, env: env)
  raise "Benchmark failed: #{stderr}" unless st.success?

  JSON.parse(stdout)
end

def compare_metrics(label, curr, base, threshold)
  base_ips = base.fetch("ips")
  curr_ips = curr.fetch("ips")
  change = (curr_ips - base_ips) / base_ips.to_f

  { label: label, base_ips: base_ips, curr_ips: curr_ips, change: change, regressed: change < -threshold }
end

def summary_report(current_results, baseline_results, base, runs, threshold)
  summary = { runs: runs, threshold: threshold, branch: current_branch, baseline: base, metrics: {}, regressions: [], failures: [] }

  current_results.each do |label, metrics|
    correct = metrics["correct"]
    unless correct
      summary[:failures] << { label: label, reason: "correctness" }
    end
    cmp = compare_metrics(label, metrics, baseline_results[label], threshold)
    if cmp[:regressed]
      summary[:regressions] << { label: label, base_ips: cmp[:base_ips], curr_ips: cmp[:curr_ips], delta_fraction: cmp[:change] }
    end
  end

  log_regressions(summary[:regressions], threshold)
  log_failures(summary[:failures])

  summary
end

def log_regressions(regressions, threshold)
  return if regressions.empty?

  puts "\nDetected regressions (< -#{(threshold * 100).round(2)}% IPS):"
  regressions.each do |r|
    delta = r[:delta_fraction]
    base_ips = r[:base_ips]
    curr_ips = r[:curr_ips]
    delta_str = delta ? format("%+0.2f%%", delta * 100) : "n/a"
    base_str = base_ips ? format("%.6f", base_ips) : "n/a"
    curr_str = curr_ips ? format("%.6f", curr_ips) : "n/a"

    puts sprintf("%<label>30s: %<base>s -> %<curr>s IPS (change: %<delta>s)", label: r[:label], base: base_str, curr: curr_str, delta: delta_str)
  end
end

def log_failures(failures)
  return if failures.empty?

  puts "\nCorrectness failures:"
  failures.each do |f|
    puts "  - #{f[:label]}: #{f[:reason]}"
  end
end

def print_realtime_comparison(label, curr_metrics, base_metrics, threshold)
  base_ips = base_metrics["ips"]
  curr_ips = curr_metrics["ips"]
  return unless base_ips && curr_ips

  change = (curr_ips - base_ips) / base_ips.to_f
  status = change < -threshold ? "REGRESSED" : "OK"
  delta_str = format("%+0.2f%%", change * 100)
  base_str = format("%.6f", base_ips)
  curr_str = format("%.6f", curr_ips)

  puts sprintf("%<label>30s: %<base>s -> %<curr>s IPS (change: %<delta>s) [%<status>s]", label: label, base: base_str, curr: curr_str, delta: delta_str, status: status)
end
