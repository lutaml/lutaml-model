# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::TypeResolver do
  let(:registry) { Lutaml::Model::TypeRegistry.new }
  let(:custom_class) { Class.new }

  describe ".resolve" do
    context "when name is already a Class" do
      it "returns the class unchanged (pass-through)" do
        context = Lutaml::Model::TypeContext.isolated(:test, registry)
        result = described_class.resolve(custom_class, context)
        expect(result).to eq(custom_class)
      end
    end

    context "when type is in primary registry" do
      before do
        registry.register(:custom, custom_class)
      end

      it "returns the registered class" do
        context = Lutaml::Model::TypeContext.isolated(:test, registry)
        result = described_class.resolve(:custom, context)
        expect(result).to eq(custom_class)
      end

      it "accepts string name (converted to symbol)" do
        context = Lutaml::Model::TypeContext.isolated(:test, registry)
        result = described_class.resolve("custom", context)
        expect(result).to eq(custom_class)
      end
    end

    context "when type is in fallback context" do
      let(:fallback_registry) { Lutaml::Model::TypeRegistry.new }
      let(:fallback_class) { Class.new }
      let(:fallback_context) do
        Lutaml::Model::TypeContext.isolated(:fallback, fallback_registry)
      end
      let(:context) do
        Lutaml::Model::TypeContext.derived(
          id: :test,
          registry: registry,
          fallback_to: [fallback_context],
        )
      end

      before do
        fallback_registry.register(:fallback_type, fallback_class)
      end

      it "resolves from fallback when not in primary" do
        result = described_class.resolve(:fallback_type, context)
        expect(result).to eq(fallback_class)
      end

      it "prefers primary over fallback" do
        primary_class = Class.new
        registry.register(:fallback_type, primary_class)
        result = described_class.resolve(:fallback_type, context)
        expect(result).to eq(primary_class)
      end
    end

    context "with nested fallbacks" do
      let(:level2_registry) { Lutaml::Model::TypeRegistry.new }
      let(:level2_class) { Class.new }
      let(:level2_context) do
        Lutaml::Model::TypeContext.isolated(:level2, level2_registry)
      end

      let(:level1_registry) { Lutaml::Model::TypeRegistry.new }
      let(:level1_context) do
        Lutaml::Model::TypeContext.derived(
          id: :level1,
          registry: level1_registry,
          fallback_to: [level2_context],
        )
      end

      let(:root_registry) { Lutaml::Model::TypeRegistry.new }
      let(:root_context) do
        Lutaml::Model::TypeContext.derived(
          id: :root,
          registry: root_registry,
          fallback_to: [level1_context],
        )
      end

      before do
        level2_registry.register(:deep_type, level2_class)
      end

      it "resolves from nested fallbacks" do
        result = described_class.resolve(:deep_type, root_context)
        expect(result).to eq(level2_class)
      end
    end

    context "when type is not found" do
      it "raises UnknownTypeError" do
        context = Lutaml::Model::TypeContext.isolated(:test, registry)
        expect do
          described_class.resolve(:unknown, context)
        end.to raise_error(Lutaml::Model::UnknownTypeError)
      end

      it "includes context id in error message" do
        context = Lutaml::Model::TypeContext.isolated(:my_context, registry)
        expect do
          described_class.resolve(:unknown, context)
        end.to raise_error(Lutaml::Model::UnknownTypeError, /my_context/)
      end

      it "includes available types in error message" do
        registry.register(:string, Lutaml::Model::Type::String)
        registry.register(:integer, Lutaml::Model::Type::Integer)
        context = Lutaml::Model::TypeContext.isolated(:test, registry)

        expect do
          described_class.resolve(:unknown, context)
        end.to raise_error(Lutaml::Model::UnknownTypeError, /integer.*string/)
      end
    end

    context "with default context" do
      it "resolves built-in types" do
        context = Lutaml::Model::TypeContext.default
        expect(described_class.resolve(:string, context)).to eq(Lutaml::Model::Type::String)
        expect(described_class.resolve(:integer, context)).to eq(Lutaml::Model::Type::Integer)
        expect(described_class.resolve(:boolean, context)).to eq(Lutaml::Model::Type::Boolean)
        expect(described_class.resolve(:date, context)).to eq(Lutaml::Model::Type::Date)
      end
    end
  end

  describe ".resolvable?" do
    before do
      registry.register(:custom, custom_class)
    end

    it "returns true for resolvable types" do
      context = Lutaml::Model::TypeContext.isolated(:test, registry)
      expect(described_class.resolvable?(:custom, context)).to be true
    end

    it "returns false for unresolvable types" do
      context = Lutaml::Model::TypeContext.isolated(:test, registry)
      expect(described_class.resolvable?(:unknown, context)).to be false
    end

    it "returns true for Class pass-through" do
      context = Lutaml::Model::TypeContext.isolated(:test, registry)
      expect(described_class.resolvable?(custom_class, context)).to be true
    end
  end

  describe ".resolve_or_nil" do
    before do
      registry.register(:custom, custom_class)
    end

    it "returns the resolved type" do
      context = Lutaml::Model::TypeContext.isolated(:test, registry)
      expect(described_class.resolve_or_nil(:custom,
                                            context)).to eq(custom_class)
    end

    it "returns nil for unresolvable types" do
      context = Lutaml::Model::TypeContext.isolated(:test, registry)
      expect(described_class.resolve_or_nil(:unknown, context)).to be_nil
    end
  end

  describe "substitutions" do
    let(:from_class) { Class.new }
    let(:to_class) { Class.new }
    let(:substitution) do
      Lutaml::Model::TypeSubstitution.new(from_type: from_class,
                                          to_type: to_class)
    end

    before do
      registry.register(:my_type, from_class)
    end

    it "applies substitutions when resolving" do
      context = Lutaml::Model::TypeContext.derived(
        id: :test,
        registry: registry,
        substitutions: [substitution],
      )

      result = described_class.resolve(:my_type, context)
      expect(result).to eq(to_class)
    end

    it "does not apply substitution for non-matching types" do
      other_class = Class.new
      registry.register(:other_type, other_class)

      context = Lutaml::Model::TypeContext.derived(
        id: :test,
        registry: registry,
        substitutions: [substitution],
      )

      result = described_class.resolve(:other_type, context)
      expect(result).to eq(other_class)
    end
  end

  describe "integration scenarios" do
    context "with derived context using default fallback" do
      let(:custom_registry) { Lutaml::Model::TypeRegistry.new }
      let(:custom_class) { Class.new }
      let(:context) do
        Lutaml::Model::TypeContext.derived(
          id: :my_app,
          registry: custom_registry,
          fallback_to: [Lutaml::Model::TypeContext.default],
        )
      end

      before do
        custom_registry.register(:custom, custom_class)
      end

      it "resolves custom types from primary registry" do
        expect(described_class.resolve(:custom, context)).to eq(custom_class)
      end

      it "resolves built-in types from fallback" do
        expect(described_class.resolve(:string, context)).to eq(Lutaml::Model::Type::String)
        expect(described_class.resolve(:integer, context)).to eq(Lutaml::Model::Type::Integer)
      end
    end

    context "with multiple fallback contexts" do
      let(:primary_registry) { Lutaml::Model::TypeRegistry.new }
      let(:fallback1_registry) { Lutaml::Model::TypeRegistry.new }
      let(:fallback2_registry) { Lutaml::Model::TypeRegistry.new }

      let(:type_a) { Class.new }
      let(:type_b) { Class.new }

      let(:context) do
        Lutaml::Model::TypeContext.derived(
          id: :test,
          registry: primary_registry,
          fallback_to: [
            Lutaml::Model::TypeContext.isolated(:fallback1, fallback1_registry),
            Lutaml::Model::TypeContext.isolated(:fallback2, fallback2_registry),
          ],
        )
      end

      before do
        fallback1_registry.register(:type_a, type_a)
        fallback2_registry.register(:type_b, type_b)
      end

      it "searches fallbacks in order" do
        expect(described_class.resolve(:type_a, context)).to eq(type_a)
        expect(described_class.resolve(:type_b, context)).to eq(type_b)
      end

      it "prefers earlier fallbacks when type exists in multiple" do
        type_a_v2 = Class.new
        fallback2_registry.register(:type_a, type_a_v2)
        # Should get type_a from fallback1 (first in list)
        expect(described_class.resolve(:type_a, context)).to eq(type_a)
      end
    end
  end
end
