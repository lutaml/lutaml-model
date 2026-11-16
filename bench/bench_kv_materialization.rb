# frozen_string_literal: true

# Deterministic KV materialization/serialization benchmark (campaign
# instrument; no external corpora). Measures from_yamls and to_yaml on
# a seeded synthetic corpus shaped like real registry documents:
# repeatable across machines and independent of downstream-gem drift.
#
# Usage: bundle exec ruby bench/bench_kv_materialization.rb [DOCS] [ITERATIONS]

require "bundler/setup"
require "lutaml/model"
require "lutaml/yaml"

Lutaml::Model::Config.configure do |config|
  config.yaml_adapter_type = :standard
end

module KvBench
  class Entry < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :value, :integer
    attribute :active, :boolean
    attribute :tags, :string, collection: true

    key_value do
      map "name", to: :name
      map "value", to: :value
      map "active", to: :active
      map "tags", to: :tags
    end
  end

  class Meta < Lutaml::Model::Serializable
    attribute :language, :string
    attribute :source, :string
    attribute :revision, :integer

    key_value do
      map "language", to: :language
      map "source", to: :source
      map "revision", to: :revision
    end
  end

  class Doc < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :status, :string, values: %w[draft published withdrawn]
    attribute :score, :float
    attribute :meta, Meta
    attribute :entries, Entry, collection: true

    key_value do
      map "id", to: :id
      map "status", to: :status
      map "score", to: :score
      map "meta", to: :meta
      map "entries", to: :entries
    end
  end

  module_function

  def corpus(docs, seed: 42)
    rng = Random.new(seed)
    Array.new(docs) do |i|
      {
        "id" => "doc-#{i}",
        "status" => %w[draft published withdrawn][rng.rand(3)],
        "score" => (rng.rand * 100).round(3),
        "meta" => {
          "language" => %w[en fr ja][rng.rand(3)],
          "source" => "src-#{rng.rand(20)}",
          "revision" => rng.rand(50),
        },
        "entries" => Array.new(2 + rng.rand(4)) do |j|
          {
            "name" => "entry-#{i}-#{j}",
            "value" => rng.rand(10_000),
            "active" => rng.rand(2).zero?,
            "tags" => Array.new(1 + rng.rand(3)) { |t| "tag-#{rng.rand(30)}-#{t}" },
          }
        end,
      }
    end
  end

  def measure(label, docs, iterations)
    # Warm caches once (docs are already-serialized YAML strings for
    # the from_yaml lane, model instances for the to_yaml lane).
    docs.first(10).each { |d| d.is_a?(::String) ? Doc.from_yaml(d) : Doc.from_yaml(d.to_yaml) }

    times = []
    allocs = []
    iterations.times do
      GC.start
      a0 = GC.stat[:total_allocated_objects]
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      a1 = GC.stat[:total_allocated_objects]
      times << (t1 - t0)
      allocs << (a1 - a0)
    end
    ms = times.min * 1000 / docs.size
    alloc = allocs.min.to_f / docs.size
    puts format("%<label>-18s %<ms>7.3f ms/doc  %<alloc>8.1f allocs/doc",
                label: label, ms: ms, alloc: alloc)
  end
end

if $PROGRAM_NAME == __FILE__
  docs_n = (ARGV[0] || 400).to_i
  iters = (ARGV[1] || 3).to_i
  raws = KvBench.corpus(docs_n)
  yamls = raws.map(&:to_yaml)
  parsed = yamls.map { |y| KvBench::Doc.from_yaml(y) }

  puts "kv materialization bench: #{docs_n} docs, #{iters} iters"
  KvBench.measure("from_yaml", yamls, iters) do
    yamls.each { |y| KvBench::Doc.from_yaml(y) }
  end
  KvBench.measure("to_yaml", parsed, iters) do
    parsed.each(&:to_yaml)
  end
end
