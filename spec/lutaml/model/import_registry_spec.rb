# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::ImportRegistry do
  let(:registry) { described_class.new }
  let(:owner_class) { Class.new }

  describe "#initialize" do
    it "creates empty registry" do
      expect(registry.pending_imports).to be_empty
      expect(registry.resolved_classes).to be_empty
    end
  end

  describe "#defer" do
    it "creates a deferred import" do
      import = registry.defer(owner_class, method: :author, symbol: :Person)

      expect(import.owner_class).to eq(owner_class)
      expect(import.method).to eq(:author)
      expect(import.symbol).to eq(:Person)
      expect(import.resolved?).to be false
    end

    it "stores the import" do
      registry.defer(owner_class, method: :author, symbol: :Person)
      expect(registry.imports_for(owner_class).size).to eq(1)
    end

    it "allows multiple imports for same class" do
      registry.defer(owner_class, method: :author, symbol: :Person)
      registry.defer(owner_class, method: :editor, symbol: :User)

      expect(registry.imports_for(owner_class).size).to eq(2)
    end

    it "marks class as not resolved when adding new imports" do
      registry.resolve(owner_class, Lutaml::Model::TypeContext.default)
      registry.defer(owner_class, method: :author, symbol: :Person)

      expect(registry.pending?(owner_class)).to be true
    end
  end

  describe "#resolve" do
    let(:context) { Lutaml::Model::TypeContext.default }

    before do
      registry.defer(owner_class, method: :author, symbol: :string)
    end

    it "resolves imports for a class" do
      resolved = registry.resolve(owner_class, context)
      expect(resolved.size).to eq(1)
      expect(resolved.first.resolved?).to be true
    end

    it "marks class as resolved" do
      registry.resolve(owner_class, context)
      expect(registry.resolved?(owner_class)).to be true
    end

    it "returns empty array if no pending imports" do
      result = registry.resolve(Class.new, context)
      expect(result).to eq([])
    end

    it "does not re-resolve already resolved imports" do
      registry.resolve(owner_class, context)
      # Call resolve again
      resolved = registry.resolve(owner_class, context)
      expect(resolved).to eq([])
    end
  end

  describe "#resolve_all!" do
    let(:context) { Lutaml::Model::TypeContext.default }
    let(:class_a) { Class.new }
    let(:class_b) { Class.new }

    before do
      registry.defer(class_a, method: :name, symbol: :string)
      registry.defer(class_b, method: :count, symbol: :integer)
    end

    it "resolves all pending imports" do
      count = registry.resolve_all!(context)
      expect(count).to eq(2)
    end

    it "marks all classes as resolved" do
      registry.resolve_all!(context)
      expect(registry.resolved?(class_a)).to be true
      expect(registry.resolved?(class_b)).to be true
    end

    it "skips already resolved imports" do
      registry.resolve(class_a, context)
      count = registry.resolve_all!(context)
      expect(count).to eq(1) # Only class_b's import
    end

    it "continues on resolution errors" do
      # Defer an unknown type
      registry.defer(class_a, method: :unknown, symbol: :nonexistent_type)

      # Should still resolve the valid ones
      count = registry.resolve_all!(context)
      expect(count).to eq(2) # string and integer
    end
  end

  describe "#pending?" do
    it "returns false for class with no imports" do
      expect(registry.pending?(Class.new)).to be false
    end

    it "returns true for class with unresolved imports" do
      registry.defer(owner_class, method: :author, symbol: :Person)
      expect(registry.pending?(owner_class)).to be true
    end

    it "returns false after imports are resolved" do
      registry.defer(owner_class, method: :name, symbol: :string)
      registry.resolve(owner_class, Lutaml::Model::TypeContext.default)
      expect(registry.pending?(owner_class)).to be false
    end
  end

  describe "#resolved?" do
    it "returns true for class with no imports" do
      expect(registry.resolved?(Class.new)).to be true
    end

    it "returns false for class with unresolved imports" do
      registry.defer(owner_class, method: :author, symbol: :Person)
      expect(registry.resolved?(owner_class)).to be false
    end

    it "returns true after imports are resolved" do
      registry.defer(owner_class, method: :name, symbol: :string)
      registry.resolve(owner_class, Lutaml::Model::TypeContext.default)
      expect(registry.resolved?(owner_class)).to be true
    end
  end

  describe "#imports_for" do
    it "returns empty array for class with no imports" do
      expect(registry.imports_for(Class.new)).to eq([])
    end

    it "returns all imports for a class" do
      registry.defer(owner_class, method: :author, symbol: :Person)
      registry.defer(owner_class, method: :editor, symbol: :User)

      imports = registry.imports_for(owner_class)
      expect(imports.size).to eq(2)
      expect(imports.map(&:method)).to contain_exactly(:author, :editor)
    end
  end

  describe "#pending_classes" do
    it "returns empty array when no pending imports" do
      expect(registry.pending_classes).to eq([])
    end

    it "returns classes with pending imports" do
      class_a = Class.new
      class_b = Class.new

      registry.defer(class_a, method: :name, symbol: :string)
      registry.defer(class_b, method: :count, symbol: :integer)

      expect(registry.pending_classes).to contain_exactly(class_a, class_b)
    end

    it "excludes resolved classes" do
      class_a = Class.new
      class_b = Class.new

      registry.defer(class_a, method: :name, symbol: :string)
      registry.defer(class_b, method: :count, symbol: :integer)

      registry.resolve(class_a, Lutaml::Model::TypeContext.default)

      expect(registry.pending_classes).to contain_exactly(class_b)
    end
  end

  describe "#reset!" do
    before do
      registry.defer(owner_class, method: :name, symbol: :string)
      registry.resolve(owner_class, Lutaml::Model::TypeContext.default)
    end

    it "clears all pending imports" do
      registry.reset!
      expect(registry.pending_imports).to be_empty
    end

    it "clears resolved classes" do
      registry.reset!
      expect(registry.resolved_classes).to be_empty
    end
  end

  describe "#stats" do
    let(:class_a) { Class.new }
    let(:class_b) { Class.new }

    before do
      registry.defer(class_a, method: :name, symbol: :string)
      registry.defer(class_a, method: :value, symbol: :integer)
      registry.defer(class_b, method: :count, symbol: :integer)
    end

    it "returns correct statistics" do
      stats = registry.stats
      expect(stats[:total_imports]).to eq(3)
      expect(stats[:resolved_imports]).to eq(0)
      expect(stats[:pending_imports]).to eq(3)
      expect(stats[:pending_classes]).to eq(2)
    end

    it "updates statistics after resolution" do
      registry.resolve(class_a, Lutaml::Model::TypeContext.default)

      stats = registry.stats
      expect(stats[:resolved_imports]).to eq(2)
      expect(stats[:pending_imports]).to eq(1)
      expect(stats[:pending_classes]).to eq(1)
    end
  end

  describe "thread safety" do
    it "handles concurrent deferral safely" do
      threads = 10.times.map do |i|
        Thread.new do
          10.times do |j|
            registry.defer(owner_class, method: "method_#{i}_#{j}".to_sym, symbol: :string)
          end
        end
      end

      threads.each(&:join)
      expect(registry.imports_for(owner_class).size).to eq(100)
    end

    it "handles concurrent resolution safely" do
      20.times do |i|
        registry.defer(owner_class, method: "method_#{i}".to_sym, symbol: :string)
      end

      threads = 5.times.map do
        Thread.new do
          registry.resolve(owner_class, Lutaml::Model::TypeContext.default)
        end
      end

      threads.each(&:join)
      expect(registry.resolved?(owner_class)).to be true
    end
  end

  describe "DeferredImport struct" do
    it "has correct attributes" do
      import = Lutaml::Model::ImportRegistry::DeferredImport.new(
        owner_class: owner_class,
        method: :author,
        symbol: :Person,
        resolved: false
      )

      expect(import.owner_class).to eq(owner_class)
      expect(import.method).to eq(:author)
      expect(import.symbol).to eq(:Person)
      expect(import.resolved).to be false
      expect(import.resolved?).to be false
    end

    it "resolved? returns true when resolved is true" do
      import = Lutaml::Model::ImportRegistry::DeferredImport.new(
        owner_class: owner_class,
        method: :author,
        symbol: :Person,
        resolved: true
      )

      expect(import.resolved?).to be true
    end
  end
end
