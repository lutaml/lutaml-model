require "spec_helper"
require "lutaml/model"

module CustomCollectionTests
  # Basic model for testing collections

  class Publication < Lutaml::Model::Serializable
    attribute :title, :string
    attribute :year, :integer
    attribute :author, :string

    xml do
      root "publication"

      map_attribute "title", to: :title
      map_attribute "year", to: :year
      map_attribute "author", to: :author
    end

    key_value do
      map "title", to: :title
      map "year", to: :year
      map "author", to: :author
    end
  end

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

  class OrderedItemCollection < Lutaml::Model::Collection
    instances :items, Item
    ordered by: :id, order: :desc
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
            id: :key,
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
            name: :value,
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
                     description: ["details", "description"],
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
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
    end

    key_value do
      root "items"
      map "items", to: :items, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
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
        "advanced" => "CustomCollectionTests::AdvancedItem",
      }
      map_element "name", to: :name
    end

    key_value do
      map "_class", to: :_class, polymorphic_map: {
        "Basic" => "CustomCollectionTests::BasicItem",
        "Advanced" => "CustomCollectionTests::AdvancedItem",
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
        { id: "2", name: "Item 2", description: "Description 2" },
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
        { id: "2", name: "Item 2", description: "Description 2" },
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
                                                                    { id: "item2", name: "Item 2", description: "Description 2" },
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
                                                                         { id: "item2", name: "Item 2" },
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
      expect(nil_collection.items).to be_nil
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
                                                                            description: "Basic Description",
                                                                          ),
                                                                          CustomCollectionTests::AdvancedItem.new(
                                                                            _class: "advanced",
                                                                            name: "Advanced Item",
                                                                            details: "Advanced Details",
                                                                            priority: 1,
                                                                          ),
                                                                        ])

      expect(collection.to_xml.strip).to eq(xml.strip)
    end

    it "serializes to YAML with polymorphic items" do
      collection = CustomCollectionTests::PolymorphicItemCollection.new([
                                                                          CustomCollectionTests::BasicItem.new(
                                                                            _class: "Basic",
                                                                            name: "Basic Item",
                                                                            description: "Basic Description",
                                                                          ),
                                                                          CustomCollectionTests::AdvancedItem.new(
                                                                            _class: "Advanced",
                                                                            name: "Advanced Item",
                                                                            details: "Advanced Details",
                                                                            priority: 1,
                                                                          ),
                                                                        ])
      expect(collection.to_yaml.strip).to eq(yaml.strip)
    end
  end

  describe "Ordered Collection" do
    let(:collection) do
      CustomCollectionTests::OrderedItemCollection.new
    end

    let(:first_item) do
      CustomCollectionTests::Item.new(
        id: "1",
        name: "Item 1",
        description: "Description 1",
      )
    end

    let(:second_item) do
      CustomCollectionTests::Item.new(
        id: "2",
        name: "Item 2",
        description: "Description 2",
      )
    end

    it "keeps the order of the items" do
      collection << first_item
      collection << second_item

      expect(collection.items).to eq([second_item, first_item])
    end
  end

  describe "Collection methods" do
    let(:items) do
      [
        { id: "1", name: "Item 1", description: "Description 1" },
        { id: "2", name: "Item 2", description: "Description 2" },
      ]
    end

    let(:collection) { CustomCollectionTests::ItemCollection.new(items) }

    describe "#filter" do
      it "returns a new collection with filtered items" do
        filtered = collection.filter { |item| item.id == "1" }
        expect(filtered).to eq([collection[0]])
      end
    end

    describe "#reject" do
      it "returns a new collection with rejected items" do
        rejected = collection.reject { |item| item.id == "1" }
        expect(rejected).to eq([collection[1]])
      end
    end

    describe "#select" do
      it "returns a new collection with selected items" do
        selected = collection.select { |item| item.id == "1" }
        expect(selected).to eq([collection[0]])
      end
    end

    describe "#map" do
      it "returns a new collection with mapped items" do
        mapped = collection.map(&:name)
        expect(mapped).to eq(["Item 1", "Item 2"])
      end
    end

    describe "#find" do
      it "returns the first item that matches the condition" do
        found = collection.find { |item| item.id == "1" }
        expect(found).to eq(collection[0])
      end
    end

    describe "#find_all" do
      it "returns all items that match the condition" do
        found = collection.find_all { |item| item.id == "1" }
        expect(found).to eq([collection[0]])
      end
    end

    describe "#count" do
      it "returns the number of items in the collection" do
        expect(collection.count).to eq(2)
      end
    end

    describe "#empty?" do
      it "returns true if the collection is empty" do
        empty_collection = CustomCollectionTests::ItemCollection.new([])
        expect(empty_collection.empty?).to be true
      end

      it "returns false if the collection is not empty" do
        expect(collection.empty?).to be false
      end
    end
  end

  describe "Numeric Validations" do
    before do
      publication_collection = Class.new(Lutaml::Model::Collection) do
        instances(:publications, CustomCollectionTests::Publication) do
          validates :year, numericality: { greater_than: 1900 }
        end
      end
      stub_const("PublicationCollection", publication_collection)
    end

    let(:valid_publication) do
      CustomCollectionTests::Publication.new(
        title: "Publication 1",
        year: 2000,
        author: "Author 1",
      )
    end

    let(:invalid_publication) do
      CustomCollectionTests::Publication.new(
        title: "Publication 1",
        year: 1800,
        author: "Author 1",
      )
    end

    it "raises error if numeric values are not valid" do
      collection = PublicationCollection.new(
        [valid_publication, invalid_publication],
      )

      expect do
        collection.validate!
      end.to raise_error(
        Lutaml::Model::ValidationError,
        /`year value is `1800`, which is not greater than 1900`/,
      )
    end

    it "does not raise error if numeric values are valid" do
      collection = PublicationCollection.new([valid_publication])
      expect { collection.validate! }.not_to raise_error
    end
  end

  describe "Presence Validations" do
    before do
      publication_collection = Class.new(Lutaml::Model::Collection) do
        instances(:publications, CustomCollectionTests::Publication) do
          validates :title, presence: true
        end
      end
      stub_const("PublicationCollection", publication_collection)
    end

    it "raises error if title is not present" do
      collection = PublicationCollection.new(
        [CustomCollectionTests::Publication.new(
          year: 2000,
          author: "Author 1",
        )],
      )

      expect do
        collection.validate!
      end.to raise_error(
        Lutaml::Model::ValidationError,
        /`title` is required/,
      )
    end

    it "does not raise error if title is present" do
      collection = PublicationCollection.new(
        [
          CustomCollectionTests::Publication.new(
            title: "Title",
          ),
        ],
      )
      expect { collection.validate! }.not_to raise_error
    end
  end

  describe "Custom Validations" do
    before do
      publication_collection = Class.new(Lutaml::Model::Collection) do
        instances(:publications, CustomCollectionTests::Publication) do
          validate :must_have_author

          def must_have_author(publications)
            publications.each do |publication|
              next unless publication.author.nil?

              errors.add(:author, "`#{publication.title}` must have an author")
            end
          end
        end
      end
      stub_const("PublicationCollection", publication_collection)
    end

    it "validates custom values" do
      collection = PublicationCollection.new(
        [
          CustomCollectionTests::Publication.new(
            title: "Publication 1",
            author: "Author 1",
          ),
          CustomCollectionTests::Publication.new(
            title: "Publication 2",
          ),
        ],
      )

      expect do
        collection.validate!
      end.to raise_error(
        Lutaml::Model::ValidationError,
        /`Publication 2` must have an author/,
      )
    end
  end
end
