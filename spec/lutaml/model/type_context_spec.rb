# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::TypeContext do
  describe "#initialize" do
    let(:registry) { Lutaml::Model::TypeRegistry.new }
    let(:context) do
      described_class.new(
        id: :test,
        registry: registry,
        substitutions: [],
        fallback_contexts: [],
      )
    end

    it "stores id as symbol" do
      expect(context.id).to eq(:test)
    end

    it "stores registry" do
      expect(context.registry).to eq(registry)
    end

    it "stores substitutions as frozen array" do
      expect(context.substitutions).to eq([])
      expect(context.substitutions.frozen?).to be true
    end

    it "stores fallback_contexts as frozen array" do
      expect(context.fallback_contexts).to eq([])
      expect(context.fallback_contexts.frozen?).to be true
    end

    it "is frozen (immutable)" do
      expect(context.frozen?).to be true
    end
  end

  describe ".default" do
    let(:default) { described_class.default }

    it "returns a TypeContext with id :default" do
      expect(default.id).to eq(:default)
    end

    it "returns the same instance (memoized)" do
      expect(described_class.default).to eq(default)
    end

    it "has built-in types registered" do
      expect(default.has_type?(:string)).to be true
      expect(default.has_type?(:integer)).to be true
      expect(default.has_type?(:boolean)).to be true
      expect(default.has_type?(:date)).to be true
    end

    it "has no fallbacks" do
      expect(default.has_fallbacks?).to be false
      expect(default.fallback_contexts).to eq([])
    end

    it "has no substitutions" do
      expect(default.substitutions).to eq([])
    end
  end

  describe ".isolated" do
    let(:registry) { Lutaml::Model::TypeRegistry.new }
    let(:context) { described_class.isolated(:my_app, registry) }

    before do
      registry.register(:custom, Class.new)
    end

    it "creates a context with the given id" do
      expect(context.id).to eq(:my_app)
    end

    it "uses the provided registry" do
      expect(context.registry).to eq(registry)
    end

    it "has no fallbacks" do
      expect(context.has_fallbacks?).to be false
    end

    it "has only types from the provided registry" do
      expect(context.has_type?(:custom)).to be true
      expect(context.has_type?(:string)).to be false # Not inherited
    end
  end

  describe ".derived" do
    let(:registry) { Lutaml::Model::TypeRegistry.new }
    let(:custom_class) { Class.new }
    let(:substitution) do
      Lutaml::Model::TypeSubstitution.new(
        from_type: custom_class,
        to_type: Lutaml::Model::Type::String,
      )
    end

    before do
      registry.register(:custom, custom_class)
    end

    it "creates a context with the given id" do
      context = described_class.derived(id: :my_app, registry: registry)
      expect(context.id).to eq(:my_app)
    end

    it "accepts fallback context by symbol" do
      described_class.derived(
        id: :my_app,
        registry: registry,
        fallback_to: [:default],
      )
      # Note: fallback resolution requires GlobalContext which we haven't set up
      # So fallback_contexts will be empty or contain resolved contexts
    end

    it "accepts fallback context by TypeContext instance" do
      default = described_class.default
      context = described_class.derived(
        id: :my_app,
        registry: registry,
        fallback_to: [default],
      )
      expect(context.fallback_contexts).to include(default)
    end

    it "accepts substitutions as TypeSubstitution objects" do
      context = described_class.derived(
        id: :my_app,
        registry: registry,
        substitutions: [substitution],
      )
      expect(context.substitutions).to include(substitution)
    end

    it "accepts substitutions as Hash objects" do
      context = described_class.derived(
        id: :my_app,
        registry: registry,
        substitutions: [{ from_type: custom_class,
                          to_type: Lutaml::Model::Type::String }],
      )
      expect(context.substitutions.first.from_type).to eq(custom_class)
      expect(context.substitutions.first.to_type).to eq(Lutaml::Model::Type::String)
    end
  end

  describe "#add_substitution" do
    let(:registry) { Lutaml::Model::TypeRegistry.new }
    let(:context) { described_class.isolated(:test, registry) }
    let(:from_class) { Class.new }

    it "returns a new context with the substitution added" do
      new_context = context.add_substitution(
        from_type: from_class,
        to_type: Lutaml::Model::Type::String,
      )

      # Different object (not same identity)
      expect(new_context).not_to equal(context)
      # Same id
      expect(new_context.id).to eq(context.id)
      # Has the new substitution
      expect(new_context.substitutions.size).to eq(1)
    end

    it "does not modify the original context" do
      original_subs = context.substitutions.dup
      context.add_substitution(
        from_type: from_class,
        to_type: Lutaml::Model::Type::String,
      )

      expect(context.substitutions).to eq(original_subs)
    end
  end

  describe "#with_fallbacks" do
    let(:registry) { Lutaml::Model::TypeRegistry.new }
    let(:context) { described_class.isolated(:test, registry) }
    let(:default) { described_class.default }

    it "returns a new context with the fallbacks" do
      new_context = context.with_fallbacks(fallback_to: [default])

      # Different object (not same identity)
      expect(new_context).not_to equal(context)
      # Has the fallback
      expect(new_context.fallback_contexts).to include(default)
    end

    it "does not modify the original context" do
      context.with_fallbacks(fallback_to: [default])

      expect(context.fallback_contexts).to eq([])
    end
  end

  describe "#has_fallbacks?" do
    it "returns false for context without fallbacks" do
      registry = Lutaml::Model::TypeRegistry.new
      context = described_class.isolated(:test, registry)

      expect(context.has_fallbacks?).to be false
    end

    it "returns true for context with fallbacks" do
      registry = Lutaml::Model::TypeRegistry.new
      default = described_class.default
      context = described_class.derived(
        id: :test,
        registry: registry,
        fallback_to: [default],
      )

      expect(context.has_fallbacks?).to be true
    end
  end

  describe "#fallback_ids" do
    it "returns empty array for context without fallbacks" do
      registry = Lutaml::Model::TypeRegistry.new
      context = described_class.isolated(:test, registry)

      expect(context.fallback_ids).to eq([])
    end

    it "returns array of fallback context IDs" do
      registry = Lutaml::Model::TypeRegistry.new
      default = described_class.default
      context = described_class.derived(
        id: :test,
        registry: registry,
        fallback_to: [default],
      )

      expect(context.fallback_ids).to eq([:default])
    end
  end

  describe "#has_type?" do
    let(:registry) { Lutaml::Model::TypeRegistry.new }
    let(:context) { described_class.isolated(:test, registry) }
    let(:custom_class) { Class.new }

    before do
      registry.register(:custom, custom_class)
    end

    it "returns true for registered types" do
      expect(context.has_type?(:custom)).to be true
    end

    it "returns false for unregistered types" do
      expect(context.has_type?(:unknown)).to be false
    end

    it "returns false for types only in fallback contexts" do
      default = described_class.default
      context_with_fallback = described_class.derived(
        id: :test,
        registry: registry,
        fallback_to: [default],
      )

      # has_type? only checks local registry, not fallbacks
      expect(context_with_fallback.has_type?(:string)).to be false
    end
  end

  describe "#lookup_local" do
    let(:registry) { Lutaml::Model::TypeRegistry.new }
    let(:context) { described_class.isolated(:test, registry) }
    let(:custom_class) { Class.new }

    before do
      registry.register(:custom, custom_class)
    end

    it "returns the class for registered types" do
      expect(context.lookup_local(:custom)).to eq(custom_class)
    end

    it "returns nil for unregistered types" do
      expect(context.lookup_local(:unknown)).to be_nil
    end
  end

  describe "#to_s" do
    it "includes the context id" do
      registry = Lutaml::Model::TypeRegistry.new
      context = described_class.isolated(:my_context, registry)

      expect(context.to_s).to include("my_context")
    end

    it "includes fallbacks when present" do
      registry = Lutaml::Model::TypeRegistry.new
      default = described_class.default
      context = described_class.derived(
        id: :my_context,
        registry: registry,
        fallback_to: [default],
      )

      expect(context.to_s).to include("fallbacks=")
      expect(context.to_s).to include("[:default]")
    end
  end

  describe "#==" do
    it "returns true for contexts with same id" do
      registry1 = Lutaml::Model::TypeRegistry.new
      registry2 = Lutaml::Model::TypeRegistry.new

      context1 = described_class.isolated(:test, registry1)
      context2 = described_class.isolated(:test, registry2)

      expect(context1 == context2).to be true
    end

    it "returns false for contexts with different ids" do
      registry = Lutaml::Model::TypeRegistry.new

      context1 = described_class.isolated(:test1, registry)
      context2 = described_class.isolated(:test2, registry)

      expect(context1 == context2).to be false
    end

    it "returns false for non-TypeContext objects" do
      registry = Lutaml::Model::TypeRegistry.new
      context = described_class.isolated(:test, registry)

      expect(context == "test").to be false
      expect(context == nil).to be false
    end
  end

  describe "#hash" do
    it "returns the same hash for contexts with same id" do
      registry1 = Lutaml::Model::TypeRegistry.new
      registry2 = Lutaml::Model::TypeRegistry.new

      context1 = described_class.isolated(:test, registry1)
      context2 = described_class.isolated(:test, registry2)

      expect(context1.hash).to eq(context2.hash)
    end
  end

  describe ".register_builtin_types_in" do
    it "registers all built-in types" do
      registry = Lutaml::Model::TypeRegistry.new
      described_class.register_builtin_types_in(registry)

      expect(registry.registered?(:string)).to be true
      expect(registry.registered?(:integer)).to be true
      expect(registry.registered?(:boolean)).to be true
      expect(registry.registered?(:date)).to be true
      expect(registry.registered?(:time)).to be true
    end
  end
end
