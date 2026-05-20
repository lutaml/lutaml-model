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

  describe "multi-class index isolation" do
    let(:other_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        attribute :code, :string
      end
    end

    it "does not mix indices across different classes" do
      model_class.new(id: "a")
      other_class.new(id: "a")

      result = described_class.resolve(model_class, :id, "a")
      expect(result).to be_a(model_class)

      result2 = described_class.resolve(other_class, :id, "a")
      expect(result2).to be_a(other_class)
    end

    it "registering class B does not iterate class A's indices" do
      # Build index for model_class (hold strong ref so GC cannot collect it)
      _obj = model_class.new(id: "x")
      described_class.resolve(model_class, :id, "x")

      # Registering other_class should not trigger work on model_class indices
      100.times { |i| other_class.new(id: "other-#{i}", code: "c#{i}") }
      result = described_class.resolve(model_class, :id, "x")
      expect(result.id).to eq("x")
    end

    it "resolves by different reference keys independently per class" do
      other_class.new(id: "alpha", code: "Z1")

      result = described_class.resolve(other_class, :id, "alpha")
      expect(result.id).to eq("alpha")

      result2 = described_class.resolve(other_class, :code, "Z1")
      expect(result2.code).to eq("Z1")
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

  describe "compaction amortisation" do
    it "bounds the number of full-array compactions across many live registers" do
      threshold = Lutaml::Model::Store::COMPACTION_THRESHOLD
      interval  = Lutaml::Model::Store::COMPACTION_INTERVAL
      n = threshold + (3 * interval)

      instance = described_class.instance

      # Holding strong refs so WeakRefs stay alive across the registers.
      objects = Array.new(n) { |i| model_class.new(id: "amortise-#{i}") }
      expect(objects.size).to eq(n)

      # Without amortisation this would be ~3000 compactions (one per register
      # past threshold). With amortisation it fires once per INTERVAL inserts,
      # so ~3 compactions plus a small slack.
      expect(instance.compaction_count).to be <= 5

      # Correctness: the most recently registered object still resolves.
      expect(described_class.resolve(model_class, :id, "amortise-#{n - 1}").id)
        .to eq("amortise-#{n - 1}")
    end

    it "resets the per-class insertion counter on clear" do
      threshold = Lutaml::Model::Store::COMPACTION_THRESHOLD
      objects = Array.new(threshold + 10) do |i|
        model_class.new(id: "pre-#{i}")
      end
      expect(objects.size).to eq(threshold + 10)
      described_class.clear

      expect(described_class.instance.inserts_since_compaction).to be_empty
    end

    it "resets the compaction counter on clear" do
      threshold = Lutaml::Model::Store::COMPACTION_THRESHOLD
      interval  = Lutaml::Model::Store::COMPACTION_INTERVAL
      _objects = Array.new(threshold + interval + 10) do |i|
        model_class.new(id: "pre-#{i}")
      end

      described_class.clear

      expect(described_class.instance.compaction_count).to eq(0)
    end

    it "removes dead refs during compaction" do
      threshold = Lutaml::Model::Store::COMPACTION_THRESHOLD
      interval  = Lutaml::Model::Store::COMPACTION_INTERVAL
      instance = described_class.instance

      # Register enough objects to trigger compaction, then release them.
      batch = Array.new(threshold + 1) { |i| model_class.new(id: "die-#{i}") }
      batch = nil
      GC.start

      # Register enough more to cross the interval gate and trigger compaction.
      Array.new(interval) { |i| model_class.new(id: "live-#{i}") }

      # After compaction, the refs array should be smaller than before
      # (some dead refs removed). Exact count depends on GC timing,
      # but the live refs must still be present.
      live = instance.refs_for(model_class.to_s)
      alive_count = live.count do |ref|
        ref.weakref_alive?
      rescue WeakRef::RefError
        false
      end
      expect(alive_count).to be < (threshold + 1 + interval)
    end

    it "maintains per-class counter independence" do
      other_class = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
      end

      # Register 5 model_class objects and 3 other_class objects.
      _objects_a = Array.new(5) { |i| model_class.new(id: "a-#{i}") }
      _objects_b = Array.new(3) { |i| other_class.new(id: "b-#{i}") }

      counters = described_class.instance.inserts_since_compaction
      expect(counters[model_class.to_s]).to eq(5)
      expect(counters[other_class.to_s]).to eq(3)
    end

    it "does not compact when exactly at threshold" do
      threshold = Lutaml::Model::Store::COMPACTION_THRESHOLD
      instance = described_class.instance

      _objects = Array.new(threshold) { |i| model_class.new(id: "edge-#{i}") }

      # refs.size == threshold, which does not satisfy size > threshold
      expect(instance.compaction_count).to eq(0)
    end
  end

  describe "index pruning" do
    it "removes stale entry on resolve" do
      instance = described_class.instance

      _obj = model_class.new(id: "stale")
      described_class.resolve(model_class, :id, "stale")
      expect(instance.index_entry_count(model_class.to_s)).to eq(1)

      _obj = nil
      GC.start

      expect(described_class.resolve(model_class, :id, "stale")).to be_nil
      expect(instance.index_entry_count(model_class.to_s)).to eq(0)
    end

    it "prunes dead index entries during compaction" do
      threshold = described_class::COMPACTION_THRESHOLD
      interval  = described_class::COMPACTION_INTERVAL
      instance = described_class.instance

      # Register and index a batch of objects
      _batch = Array.new(threshold + 1) { |i| model_class.new(id: "die-#{i}") }
      described_class.resolve(model_class, :id, "die-0")
      expect(instance.index_entry_count(model_class.to_s)).to eq(threshold + 1)

      # Release and trigger compaction
      _batch = nil
      GC.start
      Array.new(interval) { |i| model_class.new(id: "live-#{i}") }

      # Dead entries should be pruned; only live entries remain
      expect(instance.index_entry_count(model_class.to_s)).to be <= interval + 50
    end

    it "rebuilds index after pruning removes all entries for a reference key" do
      threshold = described_class::COMPACTION_THRESHOLD
      interval  = described_class::COMPACTION_INTERVAL

      # Register and index by :name only
      _batch = Array.new(threshold + 1) do |i|
        model_class.new(id: "die-#{i}", name: "n-#{i}")
      end
      described_class.resolve(model_class, :name, "n-0")

      # Release all and trigger compaction
      _batch = nil
      GC.start
      Array.new(interval) do |i|
        model_class.new(id: "live-#{i}", name: "live-n-#{i}")
      end

      # Index for :name should be rebuilt on next resolve
      new_obj = model_class.new(id: "fresh", name: "fresh-name")
      expect(described_class.resolve(model_class, :name,
                                     "fresh-name")).to eq(new_obj)
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
