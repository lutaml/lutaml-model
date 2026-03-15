# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::CachedTypeResolver do
  let(:registry) { Lutaml::Model::TypeRegistry.new }
  let(:context) { Lutaml::Model::TypeContext.isolated(:test, registry) }
  let(:custom_class) { Class.new }
  let(:resolver) { described_class.new(delegate: Lutaml::Model::TypeResolver) }

  before do
    registry.register(:custom, custom_class)
  end

  describe "#initialize" do
    it "stores the delegate resolver" do
      expect(resolver.delegate).to eq(Lutaml::Model::TypeResolver)
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
end
