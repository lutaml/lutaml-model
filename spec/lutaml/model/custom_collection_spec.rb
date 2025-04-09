require "spec_helper"
require "lutaml/model"

module CustomCollectionTests
  # Basic model for testing collections
  class Item < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :name, :string
    attribute :description, :string

    xml do
      root "item"

      map_attribute "id", to: :id
      map_element "name", to: :name
      map_element "description", to: :description
    end

    key_value do
      map "id", to: :id
      map "name", to: :name
      map "description", to: :description
    end
  end

  # Custom collection class that extends Lutaml::Model::Collection
  class ItemCollection < Lutaml::Model::Collection
    instances :items, Item

    xml do
      root "items"
      map_element "item", to: :items
    end

    key_value do
      root "items"
      map_instances to: :items
    end
  end

  # Custom collection class that extends Lutaml::Model::Collection
  class ItemNoRootCollection < Lutaml::Model::Collection
    instances :items, Item

    xml do
      no_root

      map_element "item", to: :items
    end

    key_value do
      map_instances to: :items
    end
  end

  # Collection with keyed elements
  class KeyedItemCollection < Lutaml::Model::Collection
    instances :items, Item

    key_value do
      map to: :items,
        root_mappings: {
          id: :key
        }
    end
  end

  # Collection with keyed elements and value mapping
  class KeyedValueItemCollection < Lutaml::Model::Collection
    instances :items, Item

    key_value do
      map to: :items,
        root_mappings: {
          id: :key,
          name: :value
        }
    end
  end

  # Collection with child mappings
  class ChildMappedItemCollection < Lutaml::Model::Collection
    instances :items, Item

    key_value do
      map "items", to: :items,
        child_mappings: {
          id: :key,
          name: ["details", "name"],
          description: ["details", "description"]
        }
    end
  end

  # Collection with value map
  class ValueMappedItemCollection < Lutaml::Model::Collection
    instances :items, Item

    xml do
      root "items"
      map_element "item", to: :items, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
    end

    key_value do
      root "items"
      map "items", to: :items, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
    end
  end

  # Collection with polymorphic items
  class BaseItem < Lutaml::Model::Serializable
    attribute :_class, :string, polymorphic_class: true
    attribute :name, :string

    xml do
      map_attribute "item-type", to: :_class, polymorphic_map: {
        "basic" => "CustomCollectionTests::BasicItem",
        "advanced" => "CustomCollectionTests::AdvancedItem"
      }
      map_element "name", to: :name
    end

    key_value do
      map "_class", to: :_class, polymorphic_map: {
        "Basic" => "CustomCollectionTests::BasicItem",
        "Advanced" => "CustomCollectionTests::AdvancedItem"
      }
      map "name", to: :name
    end
  end

  class BasicItem < BaseItem
    attribute :description, :string

    xml do
      map_element "description", to: :description
    end

    key_value do
      map "description", to: :description
    end
  end

  class AdvancedItem < BaseItem
    attribute :details, :string
    attribute :priority, :integer

    xml do
      map_element "details", to: :details
      map_element "priority", to: :priority
    end

    key_value do
      map "details", to: :details
      map "priority", to: :priority
    end
  end

  class PolymorphicItemCollection < Lutaml::Model::Collection
    instances :items, BaseItem

    xml do
      root "items"

      map_element "item", to: :items
    end

    key_value do
      root "items"

      map_instances to: :items
    end
  end
end

RSpec.describe CustomCollectionTests do
  describe "ItemCollection" do
    let(:items) do
      [
        { id: "1", name: "Item 1", description: "Description 1" },
        { id: "2", name: "Item 2", description: "Description 2" }
      ]
    end

    let(:collection) { CustomCollectionTests::ItemCollection.new(items) }

    it "initializes with items" do
      expect(collection.items.size).to eq(2)
      expect(collection.items.first.id).to eq("1")
      expect(collection.items.first.name).to eq("Item 1")
      expect(collection.items.first.description).to eq("Description 1")
    end

    it "serializes to XML" do
      expected_xml = <<~XML.strip
        <items>
          <item id="1">
            <name>Item 1</name>
            <description>Description 1</description>
          </item>
          <item id="2">
            <name>Item 2</name>
            <description>Description 2</description>
          </item>
        </items>
      XML

      expect(collection.to_xml.strip).to eq(expected_xml)
    end

    it "deserializes from XML" do
      xml = <<~XML
        <items>
          <item id="1">
            <name>Item 1</name>
            <description>Description 1</description>
          </item>
          <item id="2">
            <name>Item 2</name>
            <description>Description 2</description>
          </item>
        </items>
      XML

      parsed = CustomCollectionTests::ItemCollection.from_xml(xml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first.id).to eq("1")
      expect(parsed.items.first.name).to eq("Item 1")
      expect(parsed.items.first.description).to eq("Description 1")
    end

    it "serializes to YAML" do
      expected_yaml = <<~YAML.strip
        ---
        items:
        - id: '1'
          name: Item 1
          description: Description 1
        - id: '2'
          name: Item 2
          description: Description 2
      YAML

      expect(collection.to_yaml.strip).to eq(expected_yaml)
    end

    it "deserializes from YAML" do
      yaml = <<~YAML
        ---
        items:
        - id: "1"
          name: Item 1
          description: Description 1
        - id: "2"
          name: Item 2
          description: Description 2
      YAML
      parsed = CustomCollectionTests::ItemCollection.from_yaml(yaml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first.id).to eq("1")
      expect(parsed.items.first.name).to eq("Item 1")
      expect(parsed.items.first.description).to eq("Description 1")
    end
  end

  describe "ItemNoRootCollection" do
    let(:items) do
      [
        { id: "1", name: "Item 1", description: "Description 1" },
        { id: "2", name: "Item 2", description: "Description 2" }
      ]
    end

    let(:collection) { CustomCollectionTests::ItemNoRootCollection.new(items) }

    it "serializes to XML" do
      expected_xml = <<~XML.strip
        <item id="1">
          <name>Item 1</name>
          <description>Description 1</description>
        </item>
        <item id="2">
          <name>Item 2</name>
          <description>Description 2</description>
        </item>
      XML

      expect(collection.to_xml.strip).to eq(expected_xml)
    end

    it "deserializes from XML" do
      xml = <<~XML
        <item id="1">
          <name>Item 1</name>
          <description>Description 1</description>
        </item>
        <item id="2">
          <name>Item 2</name>
          <description>Description 2</description>
        </item>
      XML

      parsed = CustomCollectionTests::ItemNoRootCollection.from_xml(xml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first.id).to eq("1")
      expect(parsed.items.first.name).to eq("Item 1")
      expect(parsed.items.first.description).to eq("Description 1")
    end

    it "serializes to YAML" do
      expected_yaml = <<~YAML.strip
        ---
        - id: '1'
          name: Item 1
          description: Description 1
        - id: '2'
          name: Item 2
          description: Description 2
      YAML

      expect(collection.to_yaml.strip).to eq(expected_yaml)
    end

    it "deserializes from YAML" do
      yaml = <<~YAML
        ---
        - id: '1'
          name: Item 1
          description: Description 1
        - id: '2'
          name: Item 2
          description: Description 2
      YAML

      parsed = CustomCollectionTests::ItemNoRootCollection.from_yaml(yaml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first.id).to eq("1")
      expect(parsed.items.first.name).to eq("Item 1")
      expect(parsed.items.first.description).to eq("Description 1")
    end
  end

  describe "KeyedItemCollection" do
    let(:yaml) do
      <<~YAML
        ---
        item1:
          name: Item 1
          description: Description 1
        item2:
          name: Item 2
          description: Description 2
      YAML
    end

    it "deserializes from YAML with keyed elements" do
      parsed = CustomCollectionTests::KeyedItemCollection.from_yaml(yaml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first.id).to eq("item1")
      expect(parsed.items.first.name).to eq("Item 1")
      expect(parsed.items.first.description).to eq("Description 1")
      expect(parsed.items.last.id).to eq("item2")
      expect(parsed.items.last.name).to eq("Item 2")
      expect(parsed.items.last.description).to eq("Description 2")
    end

    it "serializes to YAML with keyed elements" do
      collection = CustomCollectionTests::KeyedItemCollection.new([
        { id: "item1", name: "Item 1", description: "Description 1" },
        { id: "item2", name: "Item 2", description: "Description 2" }
      ])
      expect(collection.to_yaml.strip).to eq(yaml.strip)
    end
  end

  describe "KeyedValueItemCollection" do
    let(:yaml) do
      <<~YAML
        ---
        item1: Item 1
        item2: Item 2
      YAML
    end

    it "deserializes from YAML with keyed elements and value mapping" do
      parsed = CustomCollectionTests::KeyedValueItemCollection.from_yaml(yaml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first.id).to eq("item1")
      expect(parsed.items.first.name).to eq("Item 1")
      expect(parsed.items.last.id).to eq("item2")
      expect(parsed.items.last.name).to eq("Item 2")
    end

    it "serializes to YAML with keyed elements and value mapping" do
      collection = CustomCollectionTests::KeyedValueItemCollection.new([
        { id: "item1", name: "Item 1" },
        { id: "item2", name: "Item 2" }
      ])
      expect(collection.to_yaml.strip).to eq(yaml.strip)
    end
  end

  describe "ChildMappedItemCollection" do
    let(:yaml) do
      <<~YAML
        ---
        "1":
          details:
            name: Item 1
            description: Description 1
        "2":
          details:
            name: Item 2
            description: Description 2
      YAML
    end

    it "deserializes from YAML with child mappings" do
      parsed = CustomCollectionTests::ChildMappedItemCollection.from_yaml(yaml)

      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first.id).to eq("1")
      expect(parsed.items.first.name).to eq("Item 1")
      expect(parsed.items.first.description).to eq("Description 1")
      expect(parsed.items.last.id).to eq("2")
      expect(parsed.items.last.name).to eq("Item 2")
      expect(parsed.items.last.description).to eq("Description 2")
    end
  end

  describe "ValueMappedItemCollection" do
    let(:empty_collection) do
      CustomCollectionTests::ValueMappedItemCollection.from_yaml("items: []")
    end

    let(:nil_collection) do
      CustomCollectionTests::ValueMappedItemCollection.from_yaml("items:")
    end

    it "returns empty collection" do
      expect(empty_collection.items).to eq([])
    end

    it "empty collection serialized to XML is <items/>" do
      expect(empty_collection.to_xml).to include("<items/>")
    end

    it "empty collection serialized to YAML is items: []" do
      expect(empty_collection.to_yaml).to include("items: []")
    end

    it "returns nil collection" do
      expect(nil_collection.items).to eq(nil)
    end

    it "nil collection serialized to XML is <item xsi:nil=\"true\"/>" do
      expect(nil_collection.to_xml).to include("<item xsi:nil=\"true\"/>")
    end

    it "nil collection serialized to YAML is items:" do
      expect(nil_collection.to_yaml.strip).to eq("---\nitems:")
    end
  end

  describe "PolymorphicItemCollection" do
    let(:xml) do
      <<~XML
        <items>
          <item item-type="basic">
            <name>Basic Item</name>
            <description>Basic Description</description>
          </item>
          <item item-type="advanced">
            <name>Advanced Item</name>
            <details>Advanced Details</details>
            <priority>1</priority>
          </item>
        </items>
      XML
    end

    let(:yaml) do
      <<~YAML
        ---
        items:
        - _class: Basic
          name: Basic Item
          description: Basic Description
        - _class: Advanced
          name: Advanced Item
          details: Advanced Details
          priority: 1
      YAML
    end

    it "deserializes from XML with polymorphic items" do
      parsed = CustomCollectionTests::PolymorphicItemCollection.from_xml(xml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first).to be_a(CustomCollectionTests::BasicItem)
      expect(parsed.items.first.name).to eq("Basic Item")
      expect(parsed.items.first.description).to eq("Basic Description")
      expect(parsed.items.last).to be_a(CustomCollectionTests::AdvancedItem)
      expect(parsed.items.last.name).to eq("Advanced Item")
      expect(parsed.items.last.details).to eq("Advanced Details")
      expect(parsed.items.last.priority).to eq(1)
    end

    it "deserializes from YAML with polymorphic items" do
      parsed = CustomCollectionTests::PolymorphicItemCollection.from_yaml(yaml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first).to be_a(CustomCollectionTests::BasicItem)
      expect(parsed.items.first.name).to eq("Basic Item")
      expect(parsed.items.first.description).to eq("Basic Description")
      expect(parsed.items.last).to be_a(CustomCollectionTests::AdvancedItem)
      expect(parsed.items.last.name).to eq("Advanced Item")
      expect(parsed.items.last.details).to eq("Advanced Details")
      expect(parsed.items.last.priority).to eq(1)
    end

    it "serializes to XML with polymorphic items" do
      collection = CustomCollectionTests::PolymorphicItemCollection.new([
        CustomCollectionTests::BasicItem.new(
          _class: "basic",
          name: "Basic Item",
          description: "Basic Description"
        ),
        CustomCollectionTests::AdvancedItem.new(
          _class: "advanced",
          name: "Advanced Item",
          details: "Advanced Details",
          priority: 1
        )
      ])

      expect(collection.to_xml.strip).to eq(xml.strip)
    end

    it "serializes to YAML with polymorphic items" do
      collection = CustomCollectionTests::PolymorphicItemCollection.new([
        CustomCollectionTests::BasicItem.new(
          _class: "Basic",
          name: "Basic Item",
          description: "Basic Description"
        ),
        CustomCollectionTests::AdvancedItem.new(
          _class: "Advanced",
          name: "Advanced Item",
          details: "Advanced Details",
          priority: 1
        )
      ])
      expect(collection.to_yaml.strip).to eq(yaml.strip)
    end
  end
end
