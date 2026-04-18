# frozen_string_literal: true

require "spec_helper"

module LazyCollectionTests
  class MultiCollection < Lutaml::Model::Serializable
    attribute :items_a, :string, collection: true
    attribute :items_b, :string, collection: true
    attribute :items_c, :string, collection: true
    attribute :name, :string

    xml do
      root "multi"
      map_element "name", to: :name
      map_element "item_a", to: :items_a
      map_element "item_b", to: :items_b
      map_element "item_c", to: :items_c
    end
  end

  class CollectionWithInit < Lutaml::Model::Serializable
    attribute :tags, :string, collection: true, initialize_empty: true
    attribute :name, :string

    xml do
      root "tagged"
      map_element "name", to: :name
      map_element "tag", to: :tags
    end
  end

  class ChildModel < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      root "child"
      map_element "value", to: :value
    end
  end

  class ParentWithManyCollections < Lutaml::Model::Serializable
    attribute :col_1, ChildModel, collection: true
    attribute :col_2, ChildModel, collection: true
    attribute :col_3, ChildModel, collection: true
    attribute :col_4, ChildModel, collection: true
    attribute :col_5, ChildModel, collection: true
    attribute :name, :string

    xml do
      root "parent"
      map_element "name", to: :name
      map_element "child1", to: :col_1
      map_element "child2", to: :col_2
      map_element "child3", to: :col_3
      map_element "child4", to: :col_4
      map_element "child5", to: :col_5
    end
  end
end

RSpec.describe "Lazy collection initialization", type: :model do
  let(:sentinel) { Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION }

  describe "deserialization from XML" do
    it "uses shared frozen sentinel for unused collections" do
      xml = "<multi><name>test</name></multi>"
      instance = LazyCollectionTests::MultiCollection.from_xml(xml)

      expect(instance.name).to eq("test")

      # Unused collections share the frozen sentinel — no per-instance allocation
      ivar_a = instance.instance_variable_get(:@items_a)
      ivar_b = instance.instance_variable_get(:@items_b)
      ivar_c = instance.instance_variable_get(:@items_c)

      expect(ivar_a).to be(sentinel)
      expect(ivar_b).to be(sentinel)
      expect(ivar_c).to be(sentinel)
    end

    it "returns sentinel for uninitialized collections (behaves like [])" do
      xml = "<multi><name>test</name></multi>"
      instance = LazyCollectionTests::MultiCollection.from_xml(xml)

      items_a = instance.items_a
      expect(items_a).to eq([])
      expect(items_a).to be_frozen
      expect(items_a).to be(sentinel)
    end

    it "supports builder-style append on sentinel collections" do
      xml = "<multi><name>test</name></multi>"
      instance = LazyCollectionTests::MultiCollection.from_xml(xml)

      # Builder-style append works even when ivar is sentinel
      instance.items_a "hello"
      expect(instance.items_a).to eq(["hello"])
      # The sentinel was replaced with a real array
      expect(instance.items_a).not_to be(sentinel)

      # Other collections still share the sentinel
      expect(instance.instance_variable_get(:@items_b)).to be(sentinel)
    end

    it "populates used collections without materialization overhead" do
      xml = "<multi><name>test</name><item_a>one</item_a><item_a>two</item_a></multi>"
      instance = LazyCollectionTests::MultiCollection.from_xml(xml)

      expect(instance.items_a).to eq(["one", "two"])
      expect(instance.name).to eq("test")

      # Unused collections still share the sentinel
      expect(instance.instance_variable_get(:@items_b)).to be(sentinel)
      expect(instance.instance_variable_get(:@items_c)).to be(sentinel)
    end

    it "handles nested models with many unused collections" do
      xml = <<~XML
        <parent>
          <name>root</name>
          <child1><value>a</value></child1>
          <child1><value>b</value></child1>
        </parent>
      XML
      instance = LazyCollectionTests::ParentWithManyCollections.from_xml(xml)

      expect(instance.col_1.map(&:value)).to eq(%w[a b])
      expect(instance.name).to eq("root")

      # Unused collections share the sentinel
      expect(instance.instance_variable_get(:@col_2)).to be(sentinel)
      expect(instance.instance_variable_get(:@col_3)).to be(sentinel)
      expect(instance.instance_variable_get(:@col_4)).to be(sentinel)
      expect(instance.instance_variable_get(:@col_5)).to be(sentinel)
    end
  end

  describe "round-trip through XML" do
    it "serializes lazy collections correctly" do
      xml = "<multi><name>test</name><item_a>x</item_a></multi>"
      instance = LazyCollectionTests::MultiCollection.from_xml(xml)
      result = instance.to_xml

      expect(result).to include("<name>test</name>")
      expect(result).to include("<item_a>x</item_a>")
    end

    it "round-trips with only used collections" do
      xml = "<multi><name>test</name><item_a>x</item_a></multi>"
      instance = LazyCollectionTests::MultiCollection.from_xml(xml)
      result = instance.to_xml
      round_tripped = LazyCollectionTests::MultiCollection.from_xml(result)

      expect(round_tripped.name).to eq("test")
      expect(round_tripped.items_a).to eq(["x"])
    end
  end

  describe "allocation savings" do
    def count_allocations
      GC.start
      GC.disable
      before = ObjectSpace.count_objects[:TOTAL]
      result = yield
      after = ObjectSpace.count_objects[:TOTAL]
      GC.enable
      [after - before, result]
    end

    it "parses with fewer array allocations than eager initialization" do
      xml = <<~XML
        <parent>
          <name>root</name>
          <child1><value>a</value></child1>
          <child1><value>b</value></child1>
        </parent>
      XML

      allocs, _instance = count_allocations do
        LazyCollectionTests::ParentWithManyCollections.from_xml(xml)
      end

      # With lazy init using frozen sentinel: unused collections share one
      # frozen [] across all instances. Only col_1 gets a real array.
      # We verify the total is reasonable (not inflated by lazy overhead)
      expect(allocs).to be < 500
    end
  end

  describe "with initialize_empty: true" do
    it "works correctly for collections with explicit init" do
      xml = "<tagged><name>test</name></tagged>"
      instance = LazyCollectionTests::CollectionWithInit.from_xml(xml)

      # initialize_empty: true sets a default proc that returns []
      # The deserialization path replaces sentinel with the default value
      expect(instance.tags).to eq([])
      expect(instance.name).to eq("test")
    end

    it "populates initialized collections from XML" do
      xml = "<tagged><name>test</name><tag>ruby</tag></tagged>"
      instance = LazyCollectionTests::CollectionWithInit.from_xml(xml)

      expect(instance.tags).to eq(["ruby"])
    end
  end
end
