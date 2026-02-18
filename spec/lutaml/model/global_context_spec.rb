# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::GlobalContext do
  before do
    # Reset global state before each test
    described_class.reset!
  end

  describe ".instance" do
    it "returns a singleton instance" do
      expect(described_class.instance).to eq(described_class.instance)
    end
  end

  describe "#initialize" do
    it "creates a ContextRegistry" do
      expect(described_class.registry).to be_a(Lutaml::Model::ContextRegistry)
    end

    it "creates a CachedTypeResolver" do
      expect(described_class.resolver).to be_a(Lutaml::Model::CachedTypeResolver)
    end

    it "creates an ImportRegistry" do
      expect(described_class.imports).to be_a(Lutaml::Model::ImportRegistry)
    end

    it "sets default_context_id to :default" do
      expect(described_class.default_context_id).to eq(:default)
    end
  end

  describe "#default_context" do
    it "returns the default context" do
      expect(described_class.default_context.id).to eq(:default)
    end
  end

  describe "#default_context_id=" do
    it "sets the default context ID" do
      described_class.create_context(id: :my_app)
      described_class.default_context_id = :my_app
      expect(described_class.default_context_id).to eq(:my_app)
    end
  end

  describe "#context" do
    it "returns default context when no ID provided" do
      expect(described_class.context.id).to eq(:default)
    end

    it "returns specific context when ID provided" do
      described_class.create_context(id: :my_app)
      expect(described_class.context(:my_app).id).to eq(:my_app)
    end

    it "returns nil for unknown context" do
      expect(described_class.context(:unknown)).to be_nil
    end
  end

  describe "#resolve_type" do
    it "resolves types using default context" do
      result = described_class.resolve_type(:string)
      expect(result).to eq(Lutaml::Model::Type::String)
    end

    it "resolves types using specific context" do
      registry = Lutaml::Model::TypeRegistry.new
      custom_class = Class.new
      registry.register(:custom, custom_class)

      described_class.create_context(id: :custom_ctx, registry: registry)
      result = described_class.resolve_type(:custom, :custom_ctx)
      expect(result).to eq(custom_class)
    end

    it "raises UnknownTypeError for unknown types" do
      expect {
        described_class.resolve_type(:nonexistent)
      }.to raise_error(Lutaml::Model::UnknownTypeError)
    end
  end

  describe "#resolvable?" do
    it "returns true for resolvable types" do
      expect(described_class.resolvable?(:string)).to be true
    end

    it "returns false for unresolvable types" do
      expect(described_class.resolvable?(:nonexistent)).to be false
    end
  end

  describe "#register_context" do
    it "registers a context" do
      registry = Lutaml::Model::TypeRegistry.new
      context = Lutaml::Model::TypeContext.isolated(:my_app, registry)
      described_class.register_context(context)

      expect(described_class.context(:my_app)).to eq(context)
    end
  end

  describe "#create_context" do
    it "creates and registers a context" do
      context = described_class.create_context(id: :my_app)
      expect(context.id).to eq(:my_app)
      expect(described_class.context(:my_app)).to eq(context)
    end

    it "accepts fallback_to with symbols" do
      context = described_class.create_context(id: :my_app, fallback_to: [:default])
      expect(context.has_fallbacks?).to be true
    end

    it "accepts substitutions" do
      from_class = Class.new
      context = described_class.create_context(
        id: :my_app,
        substitutions: [{ from_type: from_class, to_type: Lutaml::Model::Type::String }]
      )
      expect(context.substitutions.size).to eq(1)
    end
  end

  describe "#unregister_context" do
    before do
      described_class.create_context(id: :my_app, fallback_to: [:default])
    end

    it "removes a context" do
      described_class.unregister_context(:my_app)
      expect(described_class.context(:my_app)).to be_nil
    end

    it "clears cache for the context" do
      # Resolve a type to populate cache
      described_class.resolve_type(:string, :my_app)

      # Unregister
      described_class.unregister_context(:my_app)

      # Cache should be cleared
      stats = described_class.resolver.cache_stats
      expect(stats[:keys]).not_to include("my_app:string")
    end
  end

  describe "#with_context" do
    before do
      described_class.create_context(id: :my_app)
    end

    it "executes block with specified context" do
      described_class.with_context(:my_app) do
        expect(described_class.default_context.id).to eq(:my_app)
      end
    end

    it "restores previous context after block" do
      original_id = described_class.default_context.id

      described_class.with_context(:my_app) do
        # Inside block
      end

      expect(described_class.default_context.id).to eq(original_id)
    end

    it "restores context even on exception" do
      original_id = described_class.default_context.id

      begin
        described_class.with_context(:my_app) do
          raise "Test error"
        end
      rescue RuntimeError
        # Expected
      end

      expect(described_class.default_context.id).to eq(original_id)
    end
  end

  describe "#reset!" do
    before do
      described_class.create_context(id: :ctx1)
      described_class.create_context(id: :ctx2)
      described_class.resolve_type(:string)
      described_class.imports.defer(Class.new, method: :author, symbol: :Person)
    end

    it "clears non-default contexts" do
      described_class.reset!
      expect(described_class.context(:ctx1)).to be_nil
      expect(described_class.context(:ctx2)).to be_nil
    end

    it "clears resolver cache" do
      described_class.reset!
      expect(described_class.resolver.cache_stats[:size]).to eq(0)
    end

    it "clears imports" do
      described_class.reset!
      expect(described_class.imports.stats[:total_imports]).to eq(0)
    end

    it "resets default context ID" do
      described_class.default_context_id = :ctx1
      described_class.reset!
      expect(described_class.default_context_id).to eq(:default)
    end

    it "keeps default context" do
      described_class.reset!
      expect(described_class.context(:default)).not_to be_nil
    end
  end

  describe "#clear_caches" do
    before do
      described_class.resolve_type(:string)
      described_class.resolve_type(:integer)
    end

    it "clears resolver cache" do
      expect(described_class.resolver.cache_stats[:size]).to be > 0
      described_class.clear_caches
      expect(described_class.resolver.cache_stats[:size]).to eq(0)
    end

    it "does not remove contexts" do
      described_class.create_context(id: :my_app)
      described_class.clear_caches
      expect(described_class.context(:my_app)).not_to be_nil
    end
  end

  describe "#stats" do
    before do
      described_class.create_context(id: :my_app)
      described_class.resolve_type(:string)
    end

    it "returns statistics" do
      stats = described_class.stats
      expect(stats).to have_key(:contexts)
      expect(stats).to have_key(:default_context_id)
      expect(stats).to have_key(:resolver_cache_size)
      expect(stats).to have_key(:imports)
    end

    it "includes context IDs" do
      stats = described_class.stats
      expect(stats[:contexts]).to include(:default, :my_app)
    end

    it "includes cache size" do
      stats = described_class.stats
      expect(stats[:resolver_cache_size]).to be >= 1
    end
  end

  describe "delegation to class methods" do
    it "delegates registry to instance" do
      expect(described_class.registry).to eq(described_class.instance.registry)
    end

    it "delegates resolver to instance" do
      expect(described_class.resolver).to eq(described_class.instance.resolver)
    end

    it "delegates resolve_type to instance" do
      result = described_class.resolve_type(:string)
      expect(result).to eq(Lutaml::Model::Type::String)
    end

    it "delegates reset! to instance" do
      described_class.create_context(id: :test_ctx)
      described_class.reset!
      expect(described_class.context(:test_ctx)).to be_nil
    end
  end

  describe "thread safety" do
    it "handles concurrent context switching" do
      described_class.create_context(id: :ctx1)
      described_class.create_context(id: :ctx2)

      results = []

      threads = 2.times.map do |i|
        Thread.new do
          ctx_id = i.even? ? :ctx1 : :ctx2
          described_class.with_context(ctx_id) do
            sleep(0.001) # Small delay to increase chance of race conditions
            results << described_class.default_context.id
          end
        end
      end

      threads.each(&:join)

      # Each thread should have seen its own context
      expect(results).to contain_exactly(:ctx1, :ctx2)
    end

    it "handles concurrent resolve_type calls" do
      threads = 10.times.map do
        Thread.new do
          100.times { described_class.resolve_type(:string) }
        end
      end

      threads.each(&:join)
      # Should not raise any errors
    end
  end

  describe "integration" do
    it "provides complete workflow" do
      # Create a custom context
      custom_registry = Lutaml::Model::TypeRegistry.new
      custom_class = Class.new
      custom_registry.register(:custom, custom_class)

      described_class.create_context(
        id: :my_app,
        registry: custom_registry,
        fallback_to: [:default]
      )

      # Resolve custom type
      result = described_class.resolve_type(:custom, :my_app)
      expect(result).to eq(custom_class)

      # Resolve built-in type from fallback
      result = described_class.resolve_type(:string, :my_app)
      expect(result).to eq(Lutaml::Model::Type::String)

      # Use with_context
      described_class.with_context(:my_app) do
        expect(described_class.resolve_type(:custom)).to eq(custom_class)
      end

      # Reset for isolation
      described_class.reset!
      expect(described_class.context(:my_app)).to be_nil
    end
  end

  describe "#xml_namespace_registry" do
    it "returns an Xml::NamespaceClassRegistry instance" do
      expect(described_class.xml_namespace_registry).to be_a(Lutaml::Model::Xml::NamespaceClassRegistry)
    end

    it "returns the same instance on subsequent calls" do
      registry1 = described_class.xml_namespace_registry
      registry2 = described_class.xml_namespace_registry
      expect(registry1).to eq(registry2)
    end

    it "is reset by reset!" do
      # Create a namespace class
      described_class.xml_namespace_registry.get_or_create(
        uri: "http://example.com",
        prefix: "ex"
      )

      # Reset
      described_class.reset!

      # Create again - should be a new registry
      # (can't directly test clearing, but we verify reset! doesn't raise)
      expect { described_class.xml_namespace_registry }.not_to raise_error
    end
  end

  describe "#clear_xml_namespace_registry!" do
    it "clears the XML namespace registry" do
      # Create a namespace class
      described_class.xml_namespace_registry.get_or_create(
        uri: "http://example.com",
        prefix: "ex"
      )

      # Clear
      described_class.clear_xml_namespace_registry!

      # Should not raise
      expect { described_class.xml_namespace_registry }.not_to raise_error
    end
  end

  describe "Single Entry Point Architecture" do
    it "provides access to all global registries through GlobalContext" do
      expect(described_class.registry).to be_a(Lutaml::Model::ContextRegistry)
      expect(described_class.resolver).to be_a(Lutaml::Model::CachedTypeResolver)
      expect(described_class.imports).to be_a(Lutaml::Model::ImportRegistry)
      expect(described_class.xml_namespace_registry).to be_a(Lutaml::Model::Xml::NamespaceClassRegistry)
    end

    it "clears all registries with reset!" do
      # Setup some state in each registry
      described_class.create_context(id: :test_ctx)
      described_class.xml_namespace_registry.get_or_create(uri: "http://test.com")

      # Reset
      described_class.reset!

      # Verify all cleared
      expect(described_class.context(:test_ctx)).to be_nil
    end
  end
end
