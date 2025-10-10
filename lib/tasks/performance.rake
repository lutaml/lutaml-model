# frozen_string_literal: true

require_relative "performance_comparator"

desc "Run performance benchmarks"
namespace :performance do
  desc "compare performance of current branch against base branch (default: main)"
  task :compare do
    PerformanceComparator.new.run
  end
end
