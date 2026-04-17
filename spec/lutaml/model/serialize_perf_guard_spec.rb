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
        root "model"
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

    it "initializes collection attributes" do
      instance = model_class.allocate
      instance.send(:init_deserialization_state, nil)
      expect(instance.tags).to eq([])
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
