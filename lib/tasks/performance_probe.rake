# frozen_string_literal: true

# One-command performance probe for the model pipeline (TODO.perf/01).
#
#   rake performance:probe            # steady-state i/s + allocations/op
#   rake performance:profile          # ruby-prof flat profiles (parse + dump)
#   rake performance:oneshot          # fresh-process boot+parse-once medians
desc "Performance probes for the model pipeline"
namespace :performance do
  desc "steady-state i/s and allocations per op (nested 200-item model)"
  task :probe do
    system({ "BENCH_DIR" => nil }, Gem.ruby, File.expand_path("performance_probe.rb", __dir__), "probe") || raise("probe failed")
  end

  desc "ruby-prof flat profiles for from_yaml and to_yaml"
  task :profile do
    system(Gem.ruby, File.expand_path("performance_probe.rb", __dir__), "profile") || raise("profile failed")
  end

  desc "one-shot (fresh process) boot+define and parse-once medians"
  task :oneshot do
    boots = []
    parses = []
    5.times do
      out = `#{Gem.ruby} #{File.expand_path("performance_probe.rb", __dir__)} oneshot`
      boots << Regexp.last_match(1).to_f if out =~ /boot\+define: ([\d.]+)ms/
      parses << Regexp.last_match(1).to_f if out =~ /parse-once: ([\d.]+)ms/
    end
    med = ->(a) { a.sort[a.length / 2] }
    puts format("boot+define median: %<boot>.1fms   parse-once median: %<parse>.1fms",
                boot: med.call(boots), parse: med.call(parses)) + " (#{boots.length} runs)" 
  end
end
