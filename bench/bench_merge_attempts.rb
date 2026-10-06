# frozen_string_literal: true

# lutaml-model#834: merge N benchmark-attempt JSONs into one result set,
# taking the per-fixture minimum of every metric. Contention inflates
# timings; the minimum across attempts is the least-interfered
# measurement, so gates evaluated on merged output misfire only when
# EVERY attempt was slow.
#
# Usage: ruby bench_merge_attempts.rb <merged.json> <attempt1.json> [attempt2.json ...]
#
# Attempt files may be missing (crashed attempt): missing files are
# skipped; if none exist, nothing is written and the caller's compare
# step fails on the missing merged file.
if ARGV.length < 3
  warn "Usage: #{$PROGRAM_NAME} <merged.json> <attempt1.json> [attempt2.json ...]"
  exit 1
end

merged_path = ARGV[0]
attempt_paths = ARGV[1..]

require "json"

best = {}
attempt_paths.each do |path|
  next unless File.exist?(path)

  results = JSON.parse(File.read(path))
  results.each do |label, metrics|
    cur = best[label]
    if cur
      cur["avg_time"] = [cur["avg_time"], metrics["avg_time"]].min
      cur["min_time"] = [cur["min_time"], metrics["min_time"]].min
      cur["max_time"] = [cur["max_time"], metrics["max_time"]].min
      cur["allocations"] = [cur["allocations"], metrics["allocations"]].min
      cur["ips"] = [cur["ips"], metrics["ips"]].max
    else
      best[label] = metrics.dup
    end
  end
end

if best.nil? || best.empty?
  warn "No attempt JSONs found among: #{attempt_paths.join(', ')}"
  exit 1
end

File.write(merged_path, JSON.pretty_generate(best))
puts "Merged #{attempt_paths.size} attempt file(s) into #{merged_path} (#{best.size} fixtures)"
