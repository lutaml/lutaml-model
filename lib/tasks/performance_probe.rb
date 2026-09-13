# frozen_string_literal: true

# Model-pipeline performance probe (TODO.perf/01). Run via
# rake performance:probe / :profile / :oneshot, or directly:
#   ruby lib/tasks/performance_probe.rb probe|profile|oneshot

MODE = ARGV[0] || "probe"

# One-shot mode times the require itself; every other mode needs it up front.
require "lutaml/model" unless MODE == "oneshot"

def define_models
  item = Class.new(Lutaml::Model::Serializable) do
    attribute :id, :integer
    attribute :name, :string
    attribute :tags, :string, collection: true

    key_value do
      map "id", to: :id
      map "name", to: :name
      map "tags", to: :tags
    end
  end
  root = Class.new(Lutaml::Model::Serializable) do
    attribute :item, item, collection: true

    key_value { map "item", to: :item }
  end
  [item, root]
end

def build_root(item, root, count)
  root.new(item: (0...count).map { |i| item.new(id: i, name: "Test #{i}", tags: %w[a b c]) })
end

def ips_of(seconds = 3)
  require "benchmark/ips"
  lambda do |label, &blk|
    r = Benchmark.ips(time: seconds, quiet: true) { |x| x.report(label, &blk) }
    r.entries.max_by(&:ips).ips.round(1)
  end
end

def allocs_of(&blk)
  GC.start
  before = GC.stat(:total_allocated_objects)
  50.times(&blk)
  (GC.stat(:total_allocated_objects) - before) / 50.0
end

case MODE
when "probe"
  item, root = define_models
  model = build_root(item, root, 200)
  yaml_doc = model.to_yaml
  json_doc = model.to_json
  root.from_yaml(yaml_doc)

  ips = ips_of
  puts format("%<label>s: %<ips>8.1f i/s   allocs/op: %<allocs>8.1f",
              label: "from_yaml",
              ips: ips.call("fy") { root.from_yaml(yaml_doc) },
              allocs: allocs_of { root.from_yaml(yaml_doc) })
  puts format("%<label>s: %<ips>8.1f i/s   allocs/op: %<allocs>8.1f",
              label: "to_yaml  ",
              ips: ips.call("ty") { model.to_yaml },
              allocs: allocs_of { model.to_yaml })
  puts format("%<label>s: %<ips>8.1f i/s   allocs/op: %<allocs>8.1f",
              label: "from_json",
              ips: ips.call("fj") { root.from_json(json_doc) },
              allocs: allocs_of { root.from_json(json_doc) })
  puts format("%<label>s: %<ips>8.1f i/s   allocs/op: %<allocs>8.1f",
              label: "to_json  ",
              ips: ips.call("tj") { model.to_json },
              allocs: allocs_of { model.to_json })
when "profile"
  item, root = define_models
  model = build_root(item, root, 200)
  yaml_doc = model.to_yaml
  root.from_yaml(yaml_doc)

  require "ruby-prof"
  def print_profile(profile, label)
    puts "===== #{label} (20 iterations, self-time) ====="
    printer = RubyProf::FlatPrinter.new(profile)
    begin
      printer.print($stdout, {})
    rescue ArgumentError
      printer.print($stdout)
    end
  end

  print_profile(RubyProf::Profile.profile { 20.times { root.from_yaml(yaml_doc) } }, "from_yaml")
  print_profile(RubyProf::Profile.profile { 20.times { model.to_yaml } }, "to_yaml")
when "oneshot"
  # Fresh-process mode: this script IS the one-shot body; the rake task
  # re-invokes it N times and reports medians.
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  require "lutaml/model"
  item, root = define_models
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yaml_doc = build_root(item, root, 200).to_yaml
  root.from_yaml(yaml_doc)
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  puts format("boot+define: %<boot>.1fms  parse-once: %<parse>.1fms", boot: (t1 - t0) * 1000, parse: (t2 - t1) * 1000)
end
