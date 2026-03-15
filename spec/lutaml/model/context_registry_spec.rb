# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::ContextRegistry do
  let(:registry) { described_class.new }

  describe "#initialize" do
    it "creates registry with default context" do
      expect(registry.exists?(:default)).to be true
    end

    it "has exactly one context after initialization" do
      expect(registry.size).to eq(1)
    end

    it "default context is TypeContext.default" do
      expect(registry.lookup(:default)).to eq(Lutaml::Model::TypeContext.default)
    end
  end

  describe "#register" do
    let(:custom_registry) { Lutaml::Model::TypeRegistry.new }
    let(:context) do
      Lutaml::Model::TypeContext.isolated(:custom, custom_registry)
    end

    it "registers a context" do
      registry.register(context)
      expect(registry.lookup(:custom)).to eq(context)
    end

    it "overwrites existing context with same id" do
      registry.register(context)
      new_context = Lutaml::Model::TypeContext.isolated(:custom,
                                                        custom_registry)
      registry.register(new_context)
      expect(registry.lookup(:custom)).to eq(new_context)
    end

    it "raises ArgumentError for non-TypeContext" do
      expect do
        registry.register("not a context")
      end.to raise_error(ArgumentError, /Expected TypeContext/)
    end
  end

  describe "#lookup" do
    it "returns nil for unknown context" do
      expect(registry.lookup(:unknown)).to be_nil
    end

    it "accepts string id (converted to symbol)" do
      custom_registry = Lutaml::Model::TypeRegistry.new
      context = Lutaml::Model::TypeContext.isolated(:custom, custom_registry)
      registry.register(context)

      expect(registry.lookup("custom")).to eq(context)
    end
  end

  describe "#unregister" do
    let(:custom_registry) { Lutaml::Model::TypeRegistry.new }
    let(:context) do
      Lutaml::Model::TypeContext.isolated(:custom, custom_registry)
    end

    before do
      registry.register(context)
    end

    it "removes a context" do
      result = registry.unregister(:custom)
      expect(result).to eq(context)
      expect(registry.exists?(:custom)).to be false
    end

    it "returns nil for unknown context" do
      expect(registry.unregister(:unknown)).to be_nil
    end
  end

  describe "#exists?" do
    it "returns true for existing context" do
      expect(registry.exists?(:default)).to be true
    end

    it "returns false for non-existing context" do
      expect(registry.exists?(:unknown)).to be false
    end

    it "accepts string id" do
      expect(registry.exists?("default")).to be true
    end
  end

  describe "#context_ids" do
    it "returns array of context IDs" do
      expect(registry.context_ids).to eq([:default])
    end

    it "includes all registered contexts" do
      custom_registry = Lutaml::Model::TypeRegistry.new
      context = Lutaml::Model::TypeContext.isolated(:custom, custom_registry)
      registry.register(context)

      expect(registry.context_ids).to contain_exactly(:default, :custom)
    end
  end

  describe "#size" do
    it "returns number of registered contexts" do
      expect(registry.size).to eq(1)

      custom_registry = Lutaml::Model::TypeRegistry.new
      context = Lutaml::Model::TypeContext.isolated(:custom, custom_registry)
      registry.register(context)

      expect(registry.size).to eq(2)
    end
  end

  describe "#empty?" do
    it "returns true when only default context exists" do
      expect(registry.empty?).to be true
    end

    it "returns false when additional contexts exist" do
      custom_registry = Lutaml::Model::TypeRegistry.new
      context = Lutaml::Model::TypeContext.isolated(:custom, custom_registry)
      registry.register(context)

      expect(registry.empty?).to be false
    end
  end

  describe "#create" do
    it "creates and registers a derived context" do
      context = registry.create(id: :my_app)

      expect(context).to be_a(Lutaml::Model::TypeContext)
      expect(context.id).to eq(:my_app)
      expect(registry.lookup(:my_app)).to eq(context)
    end

    it "accepts fallback_to with symbols" do
      context = registry.create(id: :my_app, fallback_to: [:default])

      expect(context.has_fallbacks?).to be true
      expect(context.fallback_ids).to include(:default)
    end

    it "accepts fallback_to with TypeContext instances" do
      default = Lutaml::Model::TypeContext.default
      context = registry.create(id: :my_app, fallback_to: [default])

      expect(context.fallback_contexts).to include(default)
    end

    it "accepts custom registry" do
      custom_registry = Lutaml::Model::TypeRegistry.new
      custom_class = Class.new
      custom_registry.register(:custom, custom_class)

      context = registry.create(id: :my_app, registry: custom_registry)

      expect(context.lookup_local(:custom)).to eq(custom_class)
    end

    it "creates new registry if not provided" do
      context = registry.create(id: :my_app)
      expect(context.registry).to be_a(Lutaml::Model::TypeRegistry)
    end

    it "accepts substitutions" do
      from_class = Class.new
      to_class = Class.new

      context = registry.create(
        id: :my_app,
        substitutions: [{ from_type: from_class, to_type: to_class }],
      )

      expect(context.substitutions.size).to eq(1)
      expect(context.substitutions.first.from_type).to eq(from_class)
    end
  end

  describe "#clear" do
    before do
      registry.create(id: :custom1)
      registry.create(id: :custom2)
    end

    it "removes all contexts except default" do
      expect(registry.size).to eq(3)
      registry.clear
      expect(registry.size).to eq(1)
      expect(registry.exists?(:default)).to be true
    end

    it "re-adds fresh default context" do
      original_default = registry.lookup(:default)
      registry.clear
      # Default context is singleton, should be same object
      expect(registry.lookup(:default)).to eq(original_default)
    end
  end

  describe "#each" do
    before do
      registry.create(id: :custom1)
      registry.create(id: :custom2)
    end

    it "yields each context" do
      ids = []
      registry.each_key { |id| ids << id }
      expect(ids).to contain_exactly(:default, :custom1, :custom2)
    end

    it "returns enumerator if no block given" do
      enumerator = registry.each
      expect(enumerator).to be_a(Enumerator)
    end
  end

  describe "thread safety" do
    it "handles concurrent registration safely" do
      threads = Array.new(10) do |i|
        Thread.new do
          custom_registry = Lutaml::Model::TypeRegistry.new
          context = Lutaml::Model::TypeContext.isolated(:"context_#{i}",
                                                        custom_registry)
          registry.register(context)
        end
      end

      threads.each(&:join)
      expect(registry.size).to eq(11) # 10 + default
    end

    it "handles concurrent lookup safely" do
      registry.create(id: :test_context)

      threads = Array.new(20) do
        Thread.new do
          100.times { registry.lookup(:test_context) }
        end
      end

      threads.each(&:join)
      # Should not raise any errors
    end
  end

  describe "integration with TypeResolver" do
    it "can resolve types from registered contexts" do
      resolver = Lutaml::Model::CachedTypeResolver.new(
        delegate: Lutaml::Model::TypeResolver,
      )

      context = registry.lookup(:default)
      result = resolver.resolve(:string, context)

      expect(result).to eq(Lutaml::Model::Type::String)
    end
  end
end
