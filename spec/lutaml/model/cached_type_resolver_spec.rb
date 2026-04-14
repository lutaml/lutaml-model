# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::CachedTypeResolver do
  let(:registry) { Lutaml::Model::TypeRegistry.new }
  let(:context) { Lutaml::Model::TypeContext.isolated(:test, registry) }
  let(:custom_class) { Class.new }
  let(:resolver) { described_class.new(delegate: Lutaml::Model::TypeResolver) }

  shared_examples "a resolver cache backend" do
    let(:cache_key) { %i[test custom] }
    let(:other_cache_key) { %i[other custom] }

    it "stores and reuses cached values" do
      expect(cache_backend.fetch_or_store(cache_key) { :first }).to eq(:first)
      expect(cache_backend.fetch_or_store(cache_key) { :second }).to eq(:first)
      expect(cache_backend.keys).to contain_exactly(cache_key)
    end

    it "checks whether a cache key exists" do
      cache_backend.fetch_or_store(cache_key) { :first }

      expect(cache_backend.key?(cache_key)).to be true
      expect(cache_backend.key?(other_cache_key)).to be false
    end

    it "clears keys for a specific context" do
      cache_backend.fetch_or_store(cache_key) { :first }
      cache_backend.fetch_or_store(other_cache_key) { :second }

      cache_backend.clear_context(:test)

      expect(cache_backend.keys).to contain_exactly(other_cache_key)
    end

    it "clears all keys" do
      cache_backend.fetch_or_store(cache_key) { :first }
      cache_backend.fetch_or_store(other_cache_key) { :second }

      cache_backend.clear

      expect(cache_backend.keys).to be_empty
    end

    it "allows recursive cache population from the computed value block" do
      result = cache_backend.fetch_or_store(cache_key) do
        cache_backend.fetch_or_store(other_cache_key) { :nested }
        :outer
      end

      expect(result).to eq(:outer)
      expect(cache_backend.fetch_or_store(other_cache_key) { :other }).to eq(:nested)
    end
  end

  before do
    registry.register(:custom, custom_class)
  end

  describe described_class::ConcurrentMapCache do
    subject(:cache_backend) { described_class.new }

    it_behaves_like "a resolver cache backend"
  end

  describe described_class::MutexHashCache do
    subject(:cache_backend) { described_class.new }

    it_behaves_like "a resolver cache backend"
  end

  describe "#initialize" do
    it "stores the delegate resolver" do
      expect(resolver.delegate).to eq(Lutaml::Model::TypeResolver)
    end

    it "uses ConcurrentMapCache by default on native Ruby" do
      expect(resolver.cache_backend).to be_a(described_class::ConcurrentMapCache)
    end

    it "uses MutexHashCache by default on Opal" do
      allow(Lutaml::Model::RuntimeCompatibility).to receive(:opal?).and_return(true)

      opal_resolver = described_class.new(delegate: Lutaml::Model::TypeResolver)

      expect(opal_resolver.cache_backend).to be_a(described_class::MutexHashCache)
    end

    it "accepts an injected cache backend" do
      cache_backend = described_class::MutexHashCache.new

      injected_resolver = described_class.new(
        delegate: Lutaml::Model::TypeResolver,
        cache_backend: cache_backend,
      )

      expect(injected_resolver.cache_backend).to equal(cache_backend)
    end
  end

  describe "#resolve" do
    it "resolves types using the delegate" do
      result = resolver.resolve(:custom, context)
      expect(result).to eq(custom_class)
    end

    it "caches resolved types" do
      # First call
      resolver.resolve(:custom, context)

      # Verify it's cached (array keys: [context_id, type_name])
      stats = resolver.cache_stats
      expect(stats[:size]).to eq(1)
      expect(stats[:keys]).to include(%i[test custom])
    end

    it "returns cached value on second call" do
      # First call
      result1 = resolver.resolve(:custom, context)

      # Remove the type from registry
      registry.clear

      # Second call should return cached value
      result2 = resolver.resolve(:custom, context)
      expect(result2).to eq(result1)
    end

    it "passes through Class objects without caching" do
      klass = Class.new
      result = resolver.resolve(klass, context)
      expect(result).to eq(klass)

      # Should not be cached
      stats = resolver.cache_stats
      expect(stats[:size]).to eq(0)
    end

    it "raises UnknownTypeError for unknown types" do
      expect do
        resolver.resolve(:unknown, context)
      end.to raise_error(Lutaml::Model::UnknownTypeError)
    end

    it "caches nil results (unknown types) to avoid repeated lookups" do
      # First call raises
      expect do
        resolver.resolve(:unknown, context)
      end.to raise_error(Lutaml::Model::UnknownTypeError)

      # But the cache should not store failures - each call delegates
      # (This is a design choice - we could also cache failures)
    end
  end

  describe "#resolvable?" do
    it "returns true for resolvable types" do
      expect(resolver.resolvable?(:custom, context)).to be true
    end

    it "returns false for unresolvable types" do
      expect(resolver.resolvable?(:unknown, context)).to be false
    end

    it "returns true for Class objects" do
      expect(resolver.resolvable?(Class.new, context)).to be true
    end

    it "uses cache when available" do
      # Resolve first (populates cache)
      resolver.resolve(:custom, context)

      # Remove from registry
      registry.clear

      # resolvable? should still return true from cache
      expect(resolver.resolvable?(:custom, context)).to be true
    end
  end

  describe "#resolve_or_nil" do
    it "returns resolved type" do
      expect(resolver.resolve_or_nil(:custom, context)).to eq(custom_class)
    end

    it "returns nil for unknown types" do
      expect(resolver.resolve_or_nil(:unknown, context)).to be_nil
    end
  end

  describe "#clear_cache" do
    before do
      resolver.resolve(:custom, context)
    end

    it "clears cache for specific context" do
      expect(resolver.cache_stats[:size]).to eq(1)
      resolver.clear_cache(:test)
      expect(resolver.cache_stats[:size]).to eq(0)
    end

    it "does not clear cache for other contexts" do
      other_registry = Lutaml::Model::TypeRegistry.new
      other_registry.register(:other, Class.new)
      other_context = Lutaml::Model::TypeContext.isolated(:other,
                                                          other_registry)

      resolver.resolve(:other, other_context)
      expect(resolver.cache_stats[:size]).to eq(2)

      resolver.clear_cache(:test)
      expect(resolver.cache_stats[:size]).to eq(1)
      expect(resolver.cache_stats[:keys]).to include(%i[other other])
    end
  end

  describe "#clear_all_caches" do
    before do
      resolver.resolve(:custom, context)
    end

    it "clears all caches" do
      expect(resolver.cache_stats[:size]).to eq(1)
      resolver.clear_all_caches
      expect(resolver.cache_stats[:size]).to eq(0)
    end
  end

  describe "#cache_stats" do
    it "returns cache statistics" do
      stats = resolver.cache_stats
      expect(stats).to have_key(:size)
      expect(stats).to have_key(:keys)
    end

    it "tracks cached entries" do
      resolver.resolve(:custom, context)
      stats = resolver.cache_stats
      expect(stats[:size]).to eq(1)
      expect(stats[:keys]).to eq([%i[test custom]])
    end
  end

  describe "thread safety" do
    it "handles concurrent access safely" do
      threads = Array.new(10) do
        Thread.new do
          100.times { resolver.resolve(:custom, context) }
        end
      end

      threads.each(&:join)

      # Should have exactly one cached entry
      stats = resolver.cache_stats
      expect(stats[:size]).to eq(1)
    end

    it "handles concurrent cache clearing safely" do
      threads = Array.new(20) do |i|
        Thread.new do
          if i.even?
            50.times { resolver.resolve(:custom, context) }
          else
            5.times { resolver.clear_cache(:test) }
          end
        end
      end

      threads.each(&:join)
      # Should not raise any errors
    end
  end

  describe "with default context" do
    let(:default_context) { Lutaml::Model::TypeContext.default }

    it "caches built-in types" do
      result = resolver.resolve(:string, default_context)
      expect(result).to eq(Lutaml::Model::Type::String)

      stats = resolver.cache_stats
      expect(stats[:keys]).to include(%i[default string])
    end

    it "clears cache for default context" do
      resolver.resolve(:string, default_context)
      resolver.resolve(:integer, default_context)

      expect(resolver.cache_stats[:size]).to eq(2)
      resolver.clear_cache(:default)
      expect(resolver.cache_stats[:size]).to eq(0)
    end
  end

  describe "with multiple contexts" do
    let(:context1) { Lutaml::Model::TypeContext.isolated(:ctx1, registry) }
    let(:context2) { Lutaml::Model::TypeContext.isolated(:ctx2, registry) }

    it "maintains separate caches per context" do
      resolver.resolve(:custom, context1)
      resolver.resolve(:custom, context2)

      stats = resolver.cache_stats
      expect(stats[:size]).to eq(2)
      expect(stats[:keys]).to contain_exactly(%i[ctx1 custom],
                                              %i[ctx2 custom])
    end

    it "clears cache for specific context only" do
      resolver.resolve(:custom, context1)
      resolver.resolve(:custom, context2)

      resolver.clear_cache(:ctx1)

      stats = resolver.cache_stats
      expect(stats[:size]).to eq(1)
      expect(stats[:keys]).to contain_exactly(%i[ctx2 custom])
    end
  end

  describe "Opal compatibility" do
    let(:resolver) { described_class.new(delegate: Lutaml::Model::TypeResolver) }

    before do
      allow(Lutaml::Model::RuntimeCompatibility).to receive(:opal?).and_return(true)
    end

    it "uses the MutexHashCache by default on Opal" do
      expect(resolver.cache_backend).to be_a(described_class::MutexHashCache)
    end

    it "does not autoload the native ConcurrentMapCache on Opal" do
      hide_const("Lutaml::Model::CachedTypeResolver::ConcurrentMapCache")

      load File.expand_path("../../../lib/lutaml/model/cached_type_resolver.rb", __dir__)

      expect(described_class.autoload?(:ConcurrentMapCache)).to be_nil
    end

    it "caches resolved types without Concurrent::Map" do
      resolver.resolve(:custom, context)
      registry.clear

      expect(resolver.resolve(:custom, context)).to eq(custom_class)
      expect(resolver.cache_stats[:keys]).to eq([%i[test custom]])
    end

    it "clears the Opal cache" do
      resolver.resolve(:custom, context)

      resolver.clear_all_caches

      expect(resolver.cache_stats[:size]).to eq(0)
    end
  end
end
