# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

Dir.glob("lib/tasks/**/*.rake").each { |r| load r }

# Intentionally running performance:compare on every default task execution.
# This ensures performance regression detection on every commit, despite potential CI slowdown.
task default: %i[spec performance:compare rubocop]
