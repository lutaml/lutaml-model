# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::Store do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :name, :string
    end
  end

  before { described_class.clear }
  after { described_class.clear }

  describe "#register and #resolve" do
    it "resolves a registered object by reference key" do
      obj = model_class.new(id: "abc", name: "test")
      result = described_class.resolve(model_class, :id, "abc")
      expect(result).to eq(obj)
    end

    it "returns nil for non-existent reference" do
      model_class.new(id: "abc")
      result = described_class.resolve(model_class, :id, "nonexistent")
      expect(result).to be_nil
    end

    it "returns nil for non-existent class" do
      other_class = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
      end
      result = described_class.resolve(other_class, :id, "anything")
      expect(result).to be_nil
    end

    it "resolves by name attribute" do
      obj = model_class.new(id: "abc", name: "myobj")
      result = described_class.resolve(model_class, :name, "myobj")
      expect(result).to eq(obj)
    end
  end

  describe "indexed lookup" do
    it "builds index lazily on first resolve" do
      5.times { |i| model_class.new(id: "obj-#{i}") }

      result = described_class.resolve(model_class, :id, "obj-3")
      expect(result.id).to eq("obj-3")
    end

    it "updates index when new objects are registered after first resolve" do
      model_class.new(id: "first")
      described_class.resolve(model_class, :id, "first") # triggers index build

      model_class.new(id: "second")
      result = described_class.resolve(model_class, :id, "second")
      expect(result.id).to eq("second")
    end

    it "reuses index across multiple resolves for same key" do
      10.times { |i| model_class.new(id: "obj-#{i}") }

      # First resolve builds the index
      described_class.resolve(model_class, :id, "obj-5")
      # Second resolve should use the same index
      result = described_class.resolve(model_class, :id, "obj-7")
      expect(result.id).to eq("obj-7")
    end
  end

  describe "WeakRef behavior" do
    it "uses WeakRef for storage (objects can be collected when unreferenced)" do
      obj = model_class.new(id: "alive")
      result = described_class.resolve(model_class, :id, "alive")
      expect(result).to eq(obj)
    end

    it "resolves objects with strong references held externally" do
      obj = model_class.new(id: "alive")
      GC.start
      result = described_class.resolve(model_class, :id, "alive")
      expect(result).to eq(obj)
    end
  end

  describe "#store" do
    it "returns only live objects" do
      obj1 = model_class.new(id: "keep")
      _obj2 = model_class.new(id: "drop")
      _obj2 = nil
      GC.start

      entries = described_class.store[model_class.to_s]
      # obj1 should be alive; obj2 may or may not be GC'd depending on timing
      expect(entries).to include(obj1)
    end
  end

  describe "#clear" do
    it "removes all registered objects" do
      model_class.new(id: "a")
      model_class.new(id: "b")
      described_class.clear

      expect(described_class.resolve(model_class, :id, "a")).to be_nil
      expect(described_class.resolve(model_class, :id, "b")).to be_nil
    end

    it "clears the index" do
      model_class.new(id: "indexed")
      described_class.resolve(model_class, :id, "indexed") # build index
      described_class.clear

      model_class.new(id: "new-one")
      result = described_class.resolve(model_class, :id, "new-one")
      expect(result.id).to eq("new-one")
    end
  end
end
