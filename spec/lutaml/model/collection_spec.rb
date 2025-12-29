require "spec_helper"
require "lutaml/model"

module CollectionTests
  class Pot < Lutaml::Model::Serializable
    attribute :material, Lutaml::Model::Type::String

    xml do
      root "pot"
      map_element "material", to: :material
    end
  end

  class Kiln < Lutaml::Model::Serializable
    attribute :brand, Lutaml::Model::Type::String
    attribute :pots, Pot, collection: 0..2
    attribute :temperatures, Lutaml::Model::Type::Integer, collection: true
    attribute :operators, Lutaml::Model::Type::String, collection: (1..),
                                                       default: -> {
                                                         ["Default Operator"]
                                                       }
    attribute :sensors, Lutaml::Model::Type::String, collection: 1..3,
                                                     default: -> {
                                                       ["Default Sensor"]
                                                     }

    xml do
      root "kiln"
      map_attribute "brand", to: :brand
      map_element "pot", to: :pots
      map_element "temperature", to: :temperatures
      map_element "operator", to: :operators
      map_element "sensor", to: :sensors
    end
  end

  class Address < Lutaml::Model::Serializable
    attribute :street, :string
    attribute :city, :string
    attribute :address, Address

    xml do
      root "address"
      map_element "street", to: :street
      map_element "city", with: { from: :city_from_xml, to: :city_to_xml }
      map_element "address", to: :address
    end

    def city_from_xml(model, nodes)
      model.city = nodes.first.text
    end

    def city_to_xml(model, parent, doc)
      doc.add_element(parent, "<city>#{model.city}</city>")
    end
  end

  class ReturnNilTest < Lutaml::Model::Serializable
    attribute :default_items, :string, collection: true
    attribute :regular_items, :string, collection: true, initialize_empty: true

    yaml do
      map "default_items", to: :default_items
      map "regular_items", to: :regular_items, render_default: true,
                           render_empty: true
    end
  end

  class Person < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :age, :integer

    xml do
      root "person", ordered: true
      map_element "name", to: :name
      map_element "age", to: :age
    end
  end
end

# === Polymorphic Collection Test Models ===
module PolymorphicCollectionTests
  class Animal < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :name, :string

    xml do
      root "animal"
      map_attribute "type", to: :type
      map_element "name", to: :name
    end

    key_value do
      map "type", to: :type
      map "name", to: :name
    end
  end

  class Dog < Animal
    attribute :breed, :string

    xml do
      map_element "breed", to: :breed
    end

    key_value do
      map "breed", to: :breed
    end
  end

  class Cat < Animal
    attribute :color, :string

    xml do
      map_element "color", to: :color
    end

    key_value do
      map "color", to: :color
    end
  end

  class Rabbit < Animal
    attribute :color, :string

    xml do
      map_element "color", to: :color
    end

    key_value do
      map "color", to: :color
    end
  end

  class Car < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :model, :string
  end
end

# === Polymorphic Collection Classes ===
class PolyAnimalCollectionAny < Lutaml::Model::Collection
  instances :animals, PolymorphicCollectionTests::Animal, polymorphic: true

  xml do
    root "zoo"
    map_element "animal", to: :animals, polymorphic: {
      attribute: "type",
      class_map: {
        "dog" => "PolymorphicCollectionTests::Dog",
        "cat" => "PolymorphicCollectionTests::Cat",
        "rabbit" => "PolymorphicCollectionTests::Rabbit",
      },
    }
  end

  key_value do
    root "zoo"
    map_instances to: :animals, polymorphic: {
      attribute: "type",
      class_map: {
        "dog" => "PolymorphicCollectionTests::Dog",
        "cat" => "PolymorphicCollectionTests::Cat",
        "rabbit" => "PolymorphicCollectionTests::Rabbit",
      },
    }
  end
end

class PolyAnimalCollectionSome < Lutaml::Model::Collection
  instances :animals, PolymorphicCollectionTests::Animal,
            polymorphic: [PolymorphicCollectionTests::Dog, PolymorphicCollectionTests::Cat]
end

RSpec.describe Lutaml::Model::Collection do
  let(:xml_input) do
    <<~XML
      <people>
        <person>
          <name>Bob</name>
          <age>25</age>
        </person>
        <person>
          <age>30</age>
          <name>Alice</name>
        </person>
        <person>
          <name>Charlie</name>
          <age>35</age>
        </person>
      </people>
    XML
  end

  describe CollectionTests do
    let(:pots) { [{ material: "clay" }, { material: "ceramic" }] }
    let(:temperatures) { [1200, 1300, 1400] }
    let(:operators) { ["John", "Jane"] }
    let(:sensors) { ["Temp1", "Temp2"] }
    let(:attributes) do
      {
        brand: "Skutt",
        pots: pots,
        temperatures: temperatures,
        operators: operators,
        sensors: sensors,
      }
    end
    let(:model) { CollectionTests::Kiln.new(attributes) }

    let(:model_xml) do
      <<~XML
        <kiln brand="Skutt">
          <pot>
            <material>clay</material>
          </pot>
          <pot>
            <material>ceramic</material>
          </pot>
          <temperature>1200</temperature>
          <temperature>1300</temperature>
          <temperature>1400</temperature>
          <operator>John</operator>
          <operator>Jane</operator>
          <sensor>Temp1</sensor>
          <sensor>Temp2</sensor>
        </kiln>
      XML
    end

    it "initializes with default values" do
      default_model = CollectionTests::Kiln.new
      expect(default_model.brand).to be_nil
      expect(default_model.pots).to be_nil
      expect(default_model.temperatures).to be_nil
      expect(default_model.operators).to eq(["Default Operator"])
      expect(default_model.sensors).to eq(["Default Sensor"])
    end

    it "serializes to XML" do
      expected_xml = model_xml.strip
      expect(model.to_xml.strip).to eq(expected_xml)
    end

    it "deserializes from XML" do
      sample = CollectionTests::Kiln.from_xml(model_xml)
      expect(sample.brand).to eq("Skutt")
      expect(sample.pots.size).to eq(2)
      expect(sample.pots[0].material).to eq("clay")
      expect(sample.pots[1].material).to eq("ceramic")
      expect(sample.temperatures).to eq([1200, 1300, 1400])
      expect(sample.operators).to eq(["John", "Jane"])
      expect(sample.sensors).to eq(["Temp1", "Temp2"])
    end

    it "round-trips XML" do
      xml = model.to_xml
      new_model = CollectionTests::Kiln.from_xml(xml)
      expect(new_model.brand).to eq(model.brand)
      expect(new_model.pots.size).to eq(model.pots.size)
      model.pots.each_with_index do |pot, index|
        expect(new_model.pots[index].material).to eq(pot.material)
      end
      expect(new_model.temperatures).to eq(model.temperatures)
      expect(new_model.operators).to eq(model.operators)
      expect(new_model.sensors).to eq(model.sensors)
    end

    context "when model contains self as attribute" do
      let(:xml) do
        <<~XML
          <address>
            <street>A</street>
            <city>B</city>
            <address>
              <street>C</street>
              <city>D</city>
            </address>
          </address>
        XML
      end

      it "deserializes from XML" do
        model = CollectionTests::Address.from_xml(xml)

        expect(model.street).to eq("A")
        expect(model.city).to eq("B")
        expect(model.address.street).to eq("C")
        expect(model.address.city).to eq("D")
      end

      it "round-trips XML" do
        model = CollectionTests::Address.from_xml(xml)

        expect(model.to_xml).to be_xml_equivalent_to(xml)
      end
    end

    context "when collection counts are below given ranges" do
      let(:invalid_attributes) do
        attributes.merge(operators: [], sensors: [])
      end

      it "raises ValidationError containing CollectionCountOutOfRangeError for operators" do
        kiln = CollectionTests::Kiln.new(invalid_attributes)
        expect do
          kiln.validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
          expect(error).to include(Lutaml::Model::CollectionCountOutOfRangeError)
          expect(error.error_messages).to include(a_string_matching(/operators count is 0, must be at least 1/))
        end
      end

      it "raises ValidationError containing CollectionCountOutOfRangeError for sensors" do
        kiln = CollectionTests::Kiln.new(attributes.merge(sensors: []))
        expect do
          kiln.validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
          expect(error).to include(Lutaml::Model::CollectionCountOutOfRangeError)
          expect(error.error_messages).to include(a_string_matching(/sensors count is 0, must be between 1 and 3/))
        end
      end
    end

    context "when collection with unbounded maximum exceeds minimum" do
      let(:valid_attributes) do
        attributes.merge(operators: ["John", "Jane", "Jim", "Jessica"])
      end

      it "creates the model without errors" do
        expect do
          CollectionTests::Kiln.new(valid_attributes)
        end.not_to raise_error
      end
    end

    context "when deserializing XML with invalid collection counts" do
      let(:invalid_xml) do
        <<~XML
          <kiln brand="Skutt">
            <pot>
              <material>clay</material>
            </pot>
            <pot>
              <material>ceramic</material>
            </pot>
            <pot>
              <material>porcelain</material>
            </pot>
            <temperature>1200</temperature>
            <operator>John</operator>
            <sensor>Temp1</sensor>
            <sensor>Temp2</sensor>
            <sensor>Temp3</sensor>
            <sensor>Temp4</sensor>
          </kiln>
        XML
      end

      it "raises ValidationError containing CollectionCountOutOfRangeError" do
        expect do
          CollectionTests::Kiln.from_xml(invalid_xml).validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
          expect(error).to include(Lutaml::Model::CollectionCountOutOfRangeError)
          expect(error.error_messages).to include(a_string_matching(/pots count is 3, must be between 0 and 2/))
        end
      end
    end
  end

  context "when using initialize_empty option with collections" do
    let(:parsed) { CollectionTests::ReturnNilTest.from_yaml(yaml) }
    let(:model) { CollectionTests::ReturnNilTest.new }

    let(:yaml) do
      <<~YAML
        ---
        regular_items: ~
      YAML
    end

    it "sets nil value when reading from YAML with nil value" do
      expect(parsed.default_items).to be_nil
      expect(parsed.regular_items).to be_nil
    end

    it "initializes with empty array when initialize_empty is true" do
      expect(model.regular_items).to eq([])
    end

    it "preserves initialize_empty behavior when serializing and deserializing" do
      expected_yaml = <<~YAML
        ---
        regular_items: []
      YAML

      expect(model.to_yaml).to eq(expected_yaml)
    end

    it "raises StandardError for initialize_empty without collection" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :invalid_range, :string, initialize_empty: true
        end
      end.to raise_error(StandardError,
                         /Invalid option `initialize_empty` given without `collection: true` option/)
    end
  end

  context "when specifying invalid collection ranges" do
    it "raises an error for a range with only an upper bound" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :invalid_range, Lutaml::Model::Type::String, collection: ..3
        end
      end.to raise_error(ArgumentError, /Invalid collection range/)
    end

    it "raises an error for a range where max is less than min" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :invalid_range, Lutaml::Model::Type::String,
                    collection: 9..3
        end
      end.to raise_error(ArgumentError, /Invalid collection range/)
    end

    it "raises an error for a negative range" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :invalid_range, Lutaml::Model::Type::String,
                    collection: -2..1
        end
      end.to raise_error(ArgumentError, /Invalid collection range/)
    end

    it "allows a range with only a lower bound" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :valid_range, Lutaml::Model::Type::String, collection: 1..
        end
      end.not_to raise_error
    end

    it "allows a range with both lower and upper bounds" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :valid_range, Lutaml::Model::Type::String, collection: 1..3
        end
      end.not_to raise_error
    end

    it "allows a range with zero as the lower bound" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :valid_range, Lutaml::Model::Type::String, collection: 0..3
        end
      end.not_to raise_error
    end
  end

  context "when both outer sort and inner element sort are configured" do
    it "raises a SortingConfigurationConflictError" do
      expect do
        Class.new(Lutaml::Model::Collection) do
          instances :items, CollectionTests::Person
          sort by: :name, order: :asc

          xml do
            root "people", ordered: true
            map_element "person", to: :items
          end
        end
      end.to raise_error(Lutaml::Model::SortingConfigurationConflictError)
    end
  end

  context "when only outer sort is configured" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :items, CollectionTests::Person
        sort by: :name, order: :asc

        xml do
          root "people"
          map_element "person", to: :items
        end
      end
    end

    it "sorts the output by the given field" do
      collection = collection_class.from_xml(xml_input)

      expect(collection.to_xml).to be_xml_equivalent_to(
        <<~XML,
          <people>
            <person><age>30</age><name>Alice</name></person>
            <person><name>Bob</name><age>25</age></person>
            <person><name>Charlie</name><age>35</age></person>
          </people>
        XML
      )
    end
  end

  context "when only inner element sort is configured" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :items, CollectionTests::Person

        xml do
          root "people", ordered: true
          map_element "person", to: :items
        end
      end
    end

    it "preserves the element order from XML" do
      collection = collection_class.from_xml(xml_input)

      expect(collection.to_xml).to be_xml_equivalent_to(
        "<people><person><name>Bob</name><age>25</age></person><person><age>30</age><name>Alice</name></person><person><name>Charlie</name><age>35</age></person></people>",
      )
    end
  end

  # Test for collection parsing optimization - prevents double parsing
  context "when handling simple collections with direct mapping" do
    # Define a simple model where the entire object maps to a single attribute
    let(:title_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        key_value do
          map to: :content
        end
      end
    end

    # Define a collection of such models
    let(:title_collection_class) do
      title_klass = title_class
      Class.new(Lutaml::Model::Collection) do
        instances :titles, title_klass

        key_value do
          map_instances to: :titles
        end
      end
    end

    let(:json_data) { '["Title One", "Title Two", "Title Three"]' }
    let(:yaml_data) do
      <<~YAML
        - Title One
        - Title Two
        - Title Three
      YAML
    end

    it "parses JSON without redundant parsing of collection items" do
      # This should not call from_json on each string item
      collection = title_collection_class.from_json(json_data)

      expect(collection.titles.size).to eq(3)
      expect(collection.titles[0].content).to eq("Title One")
      expect(collection.titles[1].content).to eq("Title Two")
      expect(collection.titles[2].content).to eq("Title Three")
    end

    it "parses YAML without redundant parsing of collection items" do
      # This should not call from_yaml on each string item
      collection = title_collection_class.from_yaml(yaml_data)

      expect(collection.titles.size).to eq(3)
      expect(collection.titles[0].content).to eq("Title One")
      expect(collection.titles[1].content).to eq("Title Two")
      expect(collection.titles[2].content).to eq("Title Three")
    end

    it "handles JSON round-trip correctly" do
      collection = title_collection_class.from_json(json_data)
      json_output = collection.to_json
      round_trip_collection = title_collection_class.from_json(json_output)

      expect(round_trip_collection.titles.size).to eq(3)
      expect(round_trip_collection.titles.map(&:content)).to eq(["Title One",
                                                                 "Title Two", "Title Three"])
    end

    it "handles YAML round-trip correctly" do
      collection = title_collection_class.from_yaml(yaml_data)
      yaml_output = collection.to_yaml
      round_trip_collection = title_collection_class.from_yaml(yaml_output)

      expect(round_trip_collection.titles.size).to eq(3)
      expect(round_trip_collection.titles.map(&:content)).to eq(["Title One",
                                                                 "Title Two", "Title Three"])
    end

    it "handles cross-format conversion correctly" do
      json_collection = title_collection_class.from_json(json_data)
      yaml_collection = title_collection_class.from_yaml(yaml_data)

      # Both should produce the same content
      expect(json_collection.titles.map(&:content)).to eq(yaml_collection.titles.map(&:content))

      # Converting between formats should work
      expect(title_collection_class.from_yaml(json_collection.to_yaml).titles.map(&:content))
        .to eq(["Title One", "Title Two", "Title Three"])
      expect(title_collection_class.from_json(yaml_collection.to_json).titles.map(&:content))
        .to eq(["Title One", "Title Two", "Title Three"])
    end

    it "does not attempt to parse simple string values as JSON/YAML" do
      # This test ensures that when processing ["Title One", "Title Two", "Title Three"]
      # the individual strings are not passed to JSON.parse() or YAML.parse()
      # which would fail since "Title One" is not valid JSON

      # Mock the JSON parser to ensure it's not called on individual strings
      allow(JSON).to receive(:parse).and_call_original

      collection = title_collection_class.from_json(json_data)

      # JSON.parse should only be called once on the main array, not on individual strings
      expect(JSON).to have_received(:parse).once.with(json_data, anything)
      expect(collection.titles.map(&:content)).to eq(["Title One", "Title Two",
                                                      "Title Three"])
    end
  end

  describe "Polymorphic Collection validation errors" do
    let(:dog) do
      PolymorphicCollectionTests::Dog.new(name: "Fido", breed: "Labrador")
    end
    let(:car) do
      PolymorphicCollectionTests::Car.new(name: "Tesla", model: "Model S")
    end
    let(:rabbit) do
      PolymorphicCollectionTests::Rabbit.new(name: "Fluffy", color: "Tabby")
    end

    it "raises error for non-subclass in polymorphic: true" do
      collection = PolyAnimalCollectionAny.new([dog, car])
      expect do
        collection.validate!
      end.to raise_error(Lutaml::Model::ValidationError)
    end

    it "raises error for not-in-list in polymorphic: [Dog, Cat]" do
      collection = PolyAnimalCollectionSome.new([dog, rabbit])
      expect do
        collection.validate!
      end.to raise_error(Lutaml::Model::ValidationError)
    end
  end

  describe "Polymorphic Collection (instances :animals, ..., polymorphic: [Dog, Cat])" do
    let(:dog) do
      PolymorphicCollectionTests::Dog.new(name: "Fido", breed: "Labrador")
    end
    let(:cat) do
      PolymorphicCollectionTests::Cat.new(name: "Whiskers", color: "Tabby")
    end
    let(:collection) { PolyAnimalCollectionSome.new([dog, cat]) }

    it "accepts only Dog and Cat and validates successfully" do
      expect(collection.animals.size).to eq(2)
      expect(collection.animals[0]).to be_a(PolymorphicCollectionTests::Dog)
      expect(collection.animals[1]).to be_a(PolymorphicCollectionTests::Cat)
      expect { collection.validate! }.not_to raise_error
    end
  end

  describe "Polymorphic Collection (instances :animals, ..., polymorphic: true)" do
    let(:dog) do
      PolymorphicCollectionTests::Dog.new(name: "Fido", breed: "Labrador")
    end
    let(:cat) do
      PolymorphicCollectionTests::Cat.new(name: "Whiskers", color: "Tabby")
    end
    let(:collection) { PolyAnimalCollectionAny.new([dog, cat]) }

    it "accepts any subclass and validates successfully" do
      expect(collection.animals.size).to eq(2)
      expect(collection.animals[0]).to be_a(PolymorphicCollectionTests::Dog)
      expect(collection.animals[1]).to be_a(PolymorphicCollectionTests::Cat)
      expect { collection.validate! }.not_to raise_error
    end
  end

  describe "Polymorphic Collection XML/YAML/JSON mapping" do
    let(:dog) do
      PolymorphicCollectionTests::Dog.new(name: "Fido", breed: "Labrador",
                                          type: "dog")
    end
    let(:cat) do
      PolymorphicCollectionTests::Cat.new(name: "Whiskers", color: "Tabby",
                                          type: "cat")
    end
    let(:collection) { PolyAnimalCollectionAny.new([dog, cat]) }

    let(:xml) do
      <<~XML
        <zoo>
          <animal type="dog">
            <name>Fido</name>
            <breed>Labrador</breed>
          </animal>
          <animal type="cat">
            <name>Whiskers</name>
            <color>Tabby</color>
          </animal>
        </zoo>
      XML
    end

    let(:yaml) do
      <<~YAML
        ---
        zoo:
        - type: dog
          name: Fido
          breed: Labrador
        - type: cat
          name: Whiskers
          color: Tabby
      YAML
    end

    it "deserializes from XML correctly" do
      parsed = PolyAnimalCollectionAny.from_xml(xml)
      expect(parsed.animals[0]).to be_a(PolymorphicCollectionTests::Dog)
      expect(parsed.animals[1]).to be_a(PolymorphicCollectionTests::Cat)
      expect(parsed).to eq(collection)
    end

    it "serializes to XML correctly" do
      expect(collection.to_xml.strip).to be_xml_equivalent_to(xml.strip)
    end

    it "deserializes from YAML correctly" do
      parsed = PolyAnimalCollectionAny.from_yaml(yaml)
      expect(parsed.animals[0]).to be_a(PolymorphicCollectionTests::Dog)
      expect(parsed.animals[1]).to be_a(PolymorphicCollectionTests::Cat)
      expect(parsed).to eq(collection)
    end

    it "serializes to YAML correctly" do
      expect(collection.to_yaml).to eq(yaml)
    end
  end
end
