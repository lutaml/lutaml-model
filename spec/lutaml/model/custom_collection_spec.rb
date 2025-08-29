require "spec_helper"
require "lutaml/model"

module CustomCollection
  # Custom type classes for testing collections with Register

  class Text < Lutaml::Model::Type::String
    def to_xml
      "Text class: #{value}"
    end
  end

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
    attribute :description, :text

    xml do
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
      map_key to_instance: :id
      map_instances to: :items
    end
  end

  # Collection with keyed elements and value mapping
  class KeyedValueItemCollection < Lutaml::Model::Collection
    instances :items, Item

    key_value do
      map_key to_instance: :id
      map_value as_attribute: :name
      map_instances to: :items
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
        "basic" => "CustomCollection::BasicItem",
        "advanced" => "CustomCollection::AdvancedItem",
      }
      map_element "name", to: :name
    end

    key_value do
      map "_class", to: :_class, polymorphic_map: {
        "Basic" => "CustomCollection::BasicItem",
        "Advanced" => "CustomCollection::AdvancedItem",
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

RSpec.describe CustomCollection do
  let(:items) do
    [
      { id: "1", name: "Item 1", description: "Description 1" },
      { id: "2", name: "Item 2", description: "Description 2" },
    ]
  end

  describe "ItemCollection" do
    before do
      Lutaml::Model::GlobalRegister.register(register)
      Lutaml::Model::Config.default_register = register.id
      register.register_model(CustomCollection::Text, id: :text)
    end

    let(:collection) { CustomCollection::ItemCollection.new(items) }
    let(:register) { Lutaml::Model::Register.new(:collections) }

    let(:xml) do
      <<~XML
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
    end

    let(:yaml) do
      <<~YAML.strip
        ---
        items:
        - id: '1'
          name: Item 1
          description: Description 1
        - id: '2'
          name: Item 2
          description: Description 2
      YAML
    end

    it { expect(collection.items.size).to eq(2) }
    it { expect(collection.items.first.id).to eq("1") }
    it { expect(collection.items.first.name).to eq("Item 1") }
    it { expect(collection.items.first.description).to eq("Description 1") }
    it { expect(collection.items.last.id).to eq("2") }
    it { expect(collection.items.last.name).to eq("Item 2") }
    it { expect(collection.items.last.description).to eq("Description 2") }

    it "serializes to XML" do
      register.register_global_type_substitution(
        from_type: CustomCollection::Text,
        to_type: Lutaml::Model::Type::String,
      )
      expect(collection.to_xml.strip).to eq(xml.strip)
    end

    it "deserializes from XML" do
      expect(CustomCollection::ItemCollection.from_xml(xml)).to eq(collection)
    end

    it "serializes to YAML" do
      expect(collection.to_yaml.strip).to eq(yaml)
    end

    it "deserializes from YAML" do
      expect(CustomCollection::ItemCollection.from_yaml(yaml)).to eq(collection)
    end
  end

  describe "ItemNoRootCollection" do
    before do
      Lutaml::Model::GlobalRegister.register(register)
      Lutaml::Model::Config.default_register = register
      register.register_model(CustomCollection::Text, id: :text)
    end

    let(:register) { Lutaml::Model::Register.new(:no_collections) }

    let(:no_root_collection) do
      CustomCollection::ItemNoRootCollection.new(items)
    end

    let(:xml_no_root) do
      <<~XML.strip
        <item id="1">
          <name>Item 1</name>
          <description>Description 1</description>
        </item>
        <item id="2">
          <name>Item 2</name>
          <description>Description 2</description>
        </item>
      XML
    end

    let(:expected_xml_no_root) do
      <<~XML.strip
        <item id="1">
          <name>Item 1</name>
          <description>Text class: Description 1</description>
        </item>
        <item id="2">
          <name>Item 2</name>
          <description>Text class: Description 2</description>
        </item>
      XML
    end

    let(:yaml_no_root) do
      <<~YAML.strip
        ---
        - id: '1'
          name: Item 1
          description: Description 1
        - id: '2'
          name: Item 2
          description: Description 2
      YAML
    end

    it "serializes to XML" do
      expect(no_root_collection.to_xml.strip).to eq(expected_xml_no_root)
    end

    it "deserializes from XML" do
      expect(CustomCollection::ItemNoRootCollection.from_xml(xml_no_root))
        .to eq(no_root_collection)
    end

    it "serializes to YAML" do
      expect(no_root_collection.to_yaml.strip).to eq(yaml_no_root)
    end

    it "deserializes from YAML" do
      expect(CustomCollection::ItemNoRootCollection.from_yaml(yaml_no_root))
        .to eq(no_root_collection)
    end
  end

  describe "KeyedItemCollection" do
    let(:yaml_keyed) do
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

    let(:expected_object) do
      CustomCollection::KeyedItemCollection.new(
        [
          CustomCollection::Item.new(
            id: "item1",
            name: "Item 1",
            description: "Description 1",
          ),
          CustomCollection::Item.new(
            id: "item2",
            name: "Item 2",
            description: "Description 2",
          ),
        ],
      )
    end

    it "deserializes from YAML with keyed elements" do
      parsed = CustomCollection::KeyedItemCollection.from_yaml(yaml_keyed)

      expect(parsed).to eq(expected_object)
    end

    it "serializes to YAML with keyed elements" do
      collection = CustomCollection::KeyedItemCollection.new(
        [
          { id: "item1", name: "Item 1", description: "Description 1" },
          { id: "item2", name: "Item 2", description: "Description 2" },
        ],
      )
      expect(collection.to_yaml.strip).to eq(yaml_keyed.strip)
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
      parsed = CustomCollection::KeyedValueItemCollection.from_yaml(yaml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first.id).to eq("item1")
      expect(parsed.items.first.name).to eq("Item 1")
      expect(parsed.items.last.id).to eq("item2")
      expect(parsed.items.last.name).to eq("Item 2")
    end

    it "serializes to YAML with keyed elements and value mapping" do
      collection = CustomCollection::KeyedValueItemCollection.new(
        [
          { id: "item1", name: "Item 1" },
          { id: "item2", name: "Item 2" },
        ],
      )
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
      parsed = CustomCollection::ChildMappedItemCollection.from_yaml(yaml)

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
      CustomCollection::ValueMappedItemCollection.from_yaml("items: []")
    end

    let(:nil_collection) do
      CustomCollection::ValueMappedItemCollection.from_yaml("items:")
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
      parsed = CustomCollection::PolymorphicItemCollection.from_xml(xml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first).to be_a(CustomCollection::BasicItem)
      expect(parsed.items.first.name).to eq("Basic Item")
      expect(parsed.items.first.description).to eq("Basic Description")
      expect(parsed.items.last).to be_a(CustomCollection::AdvancedItem)
      expect(parsed.items.last.name).to eq("Advanced Item")
      expect(parsed.items.last.details).to eq("Advanced Details")
      expect(parsed.items.last.priority).to eq(1)
    end

    it "deserializes from YAML with polymorphic items" do
      parsed = CustomCollection::PolymorphicItemCollection.from_yaml(yaml)
      expect(parsed.items.size).to eq(2)
      expect(parsed.items.first).to be_a(CustomCollection::BasicItem)
      expect(parsed.items.first.name).to eq("Basic Item")
      expect(parsed.items.first.description).to eq("Basic Description")
      expect(parsed.items.last).to be_a(CustomCollection::AdvancedItem)
      expect(parsed.items.last.name).to eq("Advanced Item")
      expect(parsed.items.last.details).to eq("Advanced Details")
      expect(parsed.items.last.priority).to eq(1)
    end

    it "serializes to XML with polymorphic items" do
      collection = CustomCollection::PolymorphicItemCollection.new(
        [
          CustomCollection::BasicItem.new(
            _class: "basic",
            name: "Basic Item",
            description: "Basic Description",
          ),
          CustomCollection::AdvancedItem.new(
            _class: "advanced",
            name: "Advanced Item",
            details: "Advanced Details",
            priority: 1,
          ),
        ],
      )

      expect(collection.to_xml.strip).to eq(xml.strip)
    end

    it "serializes to YAML with polymorphic items" do
      collection = CustomCollection::PolymorphicItemCollection.new(
        [
          CustomCollection::BasicItem.new(
            _class: "Basic",
            name: "Basic Item",
            description: "Basic Description",
          ),
          CustomCollection::AdvancedItem.new(
            _class: "Advanced",
            name: "Advanced Item",
            details: "Advanced Details",
            priority: 1,
          ),
        ],
      )
      expect(collection.to_yaml.strip).to eq(yaml.strip)
    end
  end

  describe "Sort Functionality" do
    let(:items) do
      [
        { id: "3", name: "Item 3", description: "Description 3" },
        { id: "1", name: "Item 1", description: "Description 1" },
        { id: "2", name: "Item 2", description: "Description 2" },
      ]
    end

    describe "with order option" do
      let(:asc_collection_class) do
        Class.new(Lutaml::Model::Collection) do
          instances :items, CustomCollection::Item
          ordered by: :id, order: :asc
        end
      end

      let(:desc_collection_class) do
        Class.new(Lutaml::Model::Collection) do
          instances :items, CustomCollection::Item
          ordered by: :id, order: :desc
        end
      end

      it "sorts items in ascending order when order: :asc is specified" do
        collection = asc_collection_class.new(items)
        expect(collection.items.map(&:id)).to eq(["1", "2", "3"])
      end

      it "sorts items in descending order when order: :desc is specified" do
        collection = desc_collection_class.new(items)
        expect(collection.items.map(&:id)).to eq(["3", "2", "1"])
      end

      it "maintains ascending order after adding new items" do
        collection = asc_collection_class.new(items)
        new_item = CustomCollection::Item.new(id: "0", name: "Item 0", description: "Description 0")
        collection << new_item
        expect(collection.items.map(&:id)).to eq(["0", "1", "2", "3"])
      end

      it "maintains descending order after adding new items" do
        collection = desc_collection_class.new(items)
        new_item = CustomCollection::Item.new(id: "4", name: "Item 4", description: "Description 4")
        collection << new_item
        expect(collection.items.map(&:id)).to eq(["4", "3", "2", "1"])
      end
    end

    describe "with proc for ordering" do
      before do
        register = Lutaml::Model::GlobalRegister.lookup(:default)
        register.register_model(CustomCollection::Text, id: :text)
      end

      let(:proc_asc_collection_class) do
        Class.new(Lutaml::Model::Collection) do
          instances :items, CustomCollection::Item
          ordered by: lambda(&:name), order: :asc
        end
      end

      let(:proc_desc_collection_class) do
        Class.new(Lutaml::Model::Collection) do
          instances :items, CustomCollection::Item
          ordered by: lambda(&:name), order: :desc
        end
      end

      let(:complex_proc_collection_class) do
        Class.new(Lutaml::Model::Collection) do
          instances :items, CustomCollection::Item
          ordered by: ->(item) { [item.name.length, item.name] }, order: :asc
        end
      end

      it "sorts items using proc in ascending order" do
        collection = proc_asc_collection_class.new(items)
        expect(collection.items.map(&:name)).to eq(["Item 1", "Item 2", "Item 3"])
      end

      it "sorts items using proc in descending order" do
        collection = proc_desc_collection_class.new(items)
        expect(collection.items.map(&:name)).to eq(["Item 3", "Item 2", "Item 1"])
      end

      it "maintains ascending order after adding new items with proc" do
        collection = proc_asc_collection_class.new(items)
        new_item = CustomCollection::Item.new(id: "0", name: "Item 0", description: "Description 0")
        collection << new_item
        expect(collection.items.map(&:name)).to eq(["Item 0", "Item 1", "Item 2", "Item 3"])
      end

      it "maintains descending order after adding new items with proc" do
        collection = proc_desc_collection_class.new(items)
        new_item = CustomCollection::Item.new(id: "4", name: "Item 4", description: "Description 4")
        collection << new_item
        expect(collection.items.map(&:name)).to eq(["Item 4", "Item 3", "Item 2", "Item 1"])
      end

      it "sorts items using complex proc for multi-level sorting" do
        # Create items with different name lengths to test complex proc
        complex_items = [
          { id: "1", name: "Z", description: "Description 1" },
          { id: "2", name: "AA", description: "Description 2" },
          { id: "3", name: "A", description: "Description 3" },
          { id: "4", name: "BB", description: "Description 4" },
        ]
        collection = complex_proc_collection_class.new(complex_items)
        # Should sort first by name length (1 char: A, Z; 2 chars: AA, BB)
        # Then by name alphabetically within same length
        expect(collection.items.map(&:name)).to eq(["A", "Z", "AA", "BB"])
      end
    end
  end

  describe "Collection methods" do
    let(:items) do
      [
        { id: "1", name: "Item 1", description: "Description 1" },
        { id: "2", name: "Item 2", description: "Description 2" },
      ]
    end

    let(:collection) { CustomCollection::ItemCollection.new(items) }

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
        empty_collection = CustomCollection::ItemCollection.new([])
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
        instances(:publications, CustomCollection::Publication) do
          validates :year, numericality: { greater_than: 1900 }
        end
      end
      stub_const("PublicationCollection", publication_collection)
    end

    let(:valid_publication) do
      CustomCollection::Publication.new(
        title: "Publication 1",
        year: 2000,
        author: "Author 1",
      )
    end

    let(:invalid_publication) do
      CustomCollection::Publication.new(
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
        instances(:publications, CustomCollection::Publication) do
          validates :title, presence: true
        end
      end
      stub_const("PublicationCollection", publication_collection)
    end

    it "raises error if title is not present" do
      collection = PublicationCollection.new(
        [CustomCollection::Publication.new(
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
          CustomCollection::Publication.new(
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
        instances(:publications, CustomCollection::Publication) do
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
          CustomCollection::Publication.new(
            title: "Publication 1",
            author: "Author 1",
          ),
          CustomCollection::Publication.new(
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
