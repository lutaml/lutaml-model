# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

RSpec.describe "Lazy nil deserialization state guard specs" do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer
      attribute :tags, :string, collection: true

      xml do
        element "model"
        map_element "name", to: :name
        map_attribute "age", to: :age
        map_element "tag", to: :tags
      end

      def self.name
        "LazyNilTestModel"
      end
    end
  end

  describe "init_deserialization_state" do
    it "sets @using_default to nil (lazy fast path)" do
      instance = model_class.allocate
      instance.send(:init_deserialization_state, nil)
      expect(instance.instance_variable_get(:@using_default)).to be_nil
    end

    it "initializes collection attributes with shared frozen sentinel" do
      instance = model_class.allocate
      instance.send(:init_deserialization_state, nil)
      # Collections are initialized with LAZY_EMPTY_COLLECTION (frozen shared [])
      # instead of per-instance Array.new — avoids allocation overhead
      expect(instance.instance_variable_get(:@tags))
        .to be(Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION)
    end

    it "allocates a per-instance array only once the collection is read" do
      instance = model_class.allocate
      instance.send(:init_deserialization_state, nil)

      tags = instance.tags

      expect(tags).to eq([])
      expect(tags).not_to be(Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION)
      expect(instance.instance_variable_get(:@tags)).to be(tags)
    end
  end

  describe "enum collection assignment cost" do
    # Duplicates are the collection reader's job, so this writer stays a plain
    # `+`. The tempting alternative — deduping here with an Array#include? per
    # appended item — makes assignment quadratic, and an enum collection has no
    # size limit. Measured where this guard was written: the rescan form takes
    # 6.35s at this size, against well under a millisecond for the `+`. The
    # budget is deliberately coarse; it exists to catch a quadratic writer, not
    # to police small regressions.
    let(:enum_values) { (1..64_000).to_a }

    let(:enum_model_class) do
      values = enum_values
      Class.new(Lutaml::Model::Serializable) do
        attribute :codes, :integer, values: values, collection: true

        def self.name
          "LargeEnumCollectionModel"
        end
      end
    end

    it "assigns a large collection without rescanning what it already holds" do
      model = enum_model_class.new

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      model.codes = enum_values
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(model.codes.size).to eq(64_000)
      expect(elapsed).to be < 0.75
    end

    it "still reads back without duplicates after repeated assignment" do
      model = enum_model_class.new

      model.codes = [1, 2, 2, 3]
      model.codes = [3, 4]

      expect(model.codes).to eq([1, 2, 3, 4])
    end
  end

  describe "using_default? fast path" do
    let(:instance) do
      inst = model_class.allocate
      inst.send(:init_deserialization_state, nil)
      inst
    end

    it "returns true without allocating hash when nil" do
      expect(instance.using_default?(:name)).to be(true)
      # No hash should have been allocated
      expect(instance.instance_variable_get(:@using_default)).to be_nil
    end
  end

  describe "value_set_for lazy allocation" do
    let(:instance) do
      inst = model_class.allocate
      inst.send(:init_deserialization_state, nil)
      inst
    end

    it "allocates Hash.new(true) on first value_set_for call" do
      expect(instance.instance_variable_get(:@using_default)).to be_nil
      instance.value_set_for(:name)
      expect(instance.instance_variable_get(:@using_default)).to be_a(Hash)
    end

    it "sets the specific attribute to false" do
      instance.value_set_for(:name)
      hash = instance.instance_variable_get(:@using_default)
      expect(hash[:name]).to be(false)
      # Other attributes still return true (Hash.new(true) default)
      expect(hash[:age]).to be(true)
    end

    it "preserves using_default? for untracked attributes" do
      instance.value_set_for(:name)
      expect(instance.using_default?(:name)).to be(false)
      expect(instance.using_default?(:age)).to be(true)
    end
  end

  describe "allocate_for_deserialization integration" do
    it "creates instance with nil using_default" do
      instance = model_class.allocate_for_deserialization(nil)
      expect(instance.instance_variable_get(:@using_default)).to be_nil
    end

    it "round-trips through XML without errors" do
      instance = model_class.new(name: "test", age: 25)
      xml = instance.to_xml
      parsed = model_class.from_xml(xml)
      expect(parsed.name).to eq("test")
      expect(parsed.age).to eq(25)
    end
  end
end
