# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::TypeRegistry do
  let(:registry) { described_class.new }

  describe "#initialize" do
    it "creates an empty registry" do
      expect(registry.empty?).to be true
      expect(registry.size).to eq(0)
      expect(registry.names).to eq([])
    end
  end

  describe "#register" do
    it "registers a type with a symbol name" do
      klass = Class.new
      result = registry.register(:my_type, klass)

      expect(result).to eq(klass)
      expect(registry.registered?(:my_type)).to be true
      expect(registry.lookup(:my_type)).to eq(klass)
    end

    it "registers a type with a string name (converted to symbol)" do
      klass = Class.new
      registry.register("my_type", klass)

      expect(registry.registered?(:my_type)).to be true
      expect(registry.lookup("my_type")).to eq(klass)
    end

    it "overwrites an existing registration" do
      klass1 = Class.new
      klass2 = Class.new

      registry.register(:my_type, klass1)
      registry.register(:my_type, klass2)

      expect(registry.lookup(:my_type)).to eq(klass2)
    end
  end

  describe "#lookup" do
    before do
      @klass = Class.new
      registry.register(:my_type, @klass)
    end

    it "returns the registered class for a symbol name" do
      expect(registry.lookup(:my_type)).to eq(@klass)
    end

    it "returns the registered class for a string name" do
      expect(registry.lookup("my_type")).to eq(@klass)
    end

    it "returns nil for an unregistered type" do
      expect(registry.lookup(:unknown)).to be_nil
    end
  end

  describe "#registered?" do
    before do
      @klass = Class.new
      registry.register(:my_type, @klass)
    end

    it "returns true for a registered type (symbol)" do
      expect(registry.registered?(:my_type)).to be true
    end

    it "returns true for a registered type (string)" do
      expect(registry.registered?("my_type")).to be true
    end

    it "returns false for an unregistered type" do
      expect(registry.registered?(:unknown)).to be false
    end
  end

  describe "#names" do
    it "returns an empty array for an empty registry" do
      expect(registry.names).to eq([])
    end

    it "returns all registered type names as symbols" do
      klass1 = Class.new
      klass2 = Class.new

      registry.register(:type_one, klass1)
      registry.register(:type_two, klass2)

      expect(registry.names).to contain_exactly(:type_one, :type_two)
    end
  end

  describe "#clear" do
    it "removes all registered types" do
      klass = Class.new
      registry.register(:my_type, klass)

      result = registry.clear

      expect(result).to eq({})
      expect(registry.empty?).to be true
      expect(registry.registered?(:my_type)).to be false
    end
  end

  describe "#empty?" do
    it "returns true for a new registry" do
      expect(registry.empty?).to be true
    end

    it "returns false after registering a type" do
      registry.register(:my_type, Class.new)
      expect(registry.empty?).to be false
    end

    it "returns true after clearing" do
      registry.register(:my_type, Class.new)
      registry.clear
      expect(registry.empty?).to be true
    end
  end

  describe "#size" do
    it "returns 0 for an empty registry" do
      expect(registry.size).to eq(0)
    end

    it "returns the number of registered types" do
      registry.register(:type1, Class.new)
      registry.register(:type2, Class.new)
      expect(registry.size).to eq(2)
    end
  end

  describe "#dup" do
    before do
      @klass1 = Class.new
      @klass2 = Class.new
      registry.register(:type1, @klass1)
      registry.register(:type2, @klass2)
    end

    it "creates a copy with the same types" do
      copy = registry.dup

      expect(copy.names).to contain_exactly(:type1, :type2)
      expect(copy.lookup(:type1)).to eq(@klass1)
      expect(copy.lookup(:type2)).to eq(@klass2)
    end

    it "creates an independent copy" do
      copy = registry.dup
      copy.register(:type3, Class.new)

      expect(registry.registered?(:type3)).to be false
      expect(copy.registered?(:type3)).to be true
    end
  end

  describe "#merge!" do
    let(:other) { described_class.new }
    let(:klass1) { Class.new }
    let(:klass2) { Class.new }
    let(:klass3) { Class.new }

    before do
      registry.register(:type1, klass1)
      other.register(:type2, klass2)
      other.register(:type3, klass3)
    end

    it "merges types from another registry" do
      registry.merge!(other)

      expect(registry.lookup(:type1)).to eq(klass1)
      expect(registry.lookup(:type2)).to eq(klass2)
      expect(registry.lookup(:type3)).to eq(klass3)
    end

    it "does not overwrite existing types" do
      klass_different = Class.new
      other.register(:type1, klass_different)

      registry.merge!(other)

      expect(registry.lookup(:type1)).to eq(klass1) # Original preserved
    end

    it "returns self for chaining" do
      result = registry.merge!(other)
      expect(result).to eq(registry)
    end
  end

  describe "#merge" do
    let(:other) { described_class.new }
    let(:klass1) { Class.new }
    let(:klass2) { Class.new }

    before do
      registry.register(:type1, klass1)
      other.register(:type2, klass2)
    end

    it "creates a new merged registry" do
      merged = registry.merge(other)

      expect(merged).not_to eq(registry)
      expect(merged).not_to eq(other)
      expect(merged.lookup(:type1)).to eq(klass1)
      expect(merged.lookup(:type2)).to eq(klass2)
    end

    it "does not modify the original registries" do
      registry.merge(other)

      expect(registry.registered?(:type2)).to be false
      expect(other.registered?(:type1)).to be false
    end
  end

  describe "integration with real type classes" do
    it "can register and lookup Lutaml::Model::Type classes" do
      registry.register(:string, Lutaml::Model::Type::String)
      registry.register(:integer, Lutaml::Model::Type::Integer)
      registry.register(:boolean, Lutaml::Model::Type::Boolean)

      expect(registry.lookup(:string)).to eq(Lutaml::Model::Type::String)
      expect(registry.lookup(:integer)).to eq(Lutaml::Model::Type::Integer)
      expect(registry.lookup(:boolean)).to eq(Lutaml::Model::Type::Boolean)
    end
  end

  describe "lazy registration with Proc" do
    it "resolves a Proc on first lookup" do
      klass = Class.new
      registry.register(:lazy_type, -> { klass })

      expect(registry.lookup(:lazy_type)).to eq(klass)
    end

    it "caches the resolved class after first lookup" do
      call_count = 0
      klass = Class.new
      registry.register(:lazy_type, -> {
        call_count += 1
        klass
      })

      registry.lookup(:lazy_type)
      registry.lookup(:lazy_type)

      expect(call_count).to eq(1)
    end

    it "returns nil for unregistered lazy types" do
      expect(registry.lookup(:unknown)).to be_nil
    end

    it "preserves lazy behavior after dup" do
      klass = Class.new
      registry.register(:lazy_type, -> { klass })

      copy = registry.dup
      expect(copy.lookup(:lazy_type)).to eq(klass)
    end

    it "does not regress when registering a Class directly" do
      klass = Class.new
      registry.register(:eager_type, klass)

      expect(registry.lookup(:eager_type)).to eq(klass)
    end

    it "works with merge!" do
      klass = Class.new
      other = described_class.new
      other.register(:lazy_type, -> { klass })

      registry.merge!(other)
      expect(registry.lookup(:lazy_type)).to eq(klass)
    end

    it "raises if Proc raises" do
      registry.register(:bad_type, -> {
        raise NameError, "uninitialized constant"
      })

      expect { registry.lookup(:bad_type) }.to raise_error(NameError)
    end

    it "does not mutate @types when Proc raises" do
      call_count = 0
      registry.register(:bad_type, -> {
        call_count += 1
        raise NameError, "uninitialized constant"
      })

      expect { registry.lookup(:bad_type) }.to raise_error(NameError)
      expect(call_count).to eq(1)

      # Retry should call the Proc again
      registry.register(:bad_type, -> { Class.new })
      expect(registry.lookup(:bad_type)).to be_a(Class)
    end
  end
end
