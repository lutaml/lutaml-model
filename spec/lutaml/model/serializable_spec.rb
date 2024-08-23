class TestModel
  attr_accessor :name, :age

  def initialize(name: nil, age: nil)
    @name = name
    @age = age
  end
end

class TestModelMapper < Lutaml::Model::Serializable
  model TestModel

  attribute :name, Lutaml::Model::Type::String
  attribute :age, Lutaml::Model::Type::String
end

class TestMapper < Lutaml::Model::Serializable
  attribute :name, Lutaml::Model::Type::String
  attribute :age, Lutaml::Model::Type::String

  yaml do
    map :na, to: :name
    map :ag, to: :age
  end
end

### XML root mapping

class RecordDate < Lutaml::Model::Serializable
  attribute :content, :string

  xml do
    root "recordDate"
    map_content to: :content
  end
end

class OriginInfo < Lutaml::Model::Serializable
  attribute :date_issued, RecordDate, collection: true

  xml do
    root "originInfo"
    map_element "dateIssued", to: :date_issued
  end
end

### Enumeration

class Ceramic < Lutaml::Model::Serializable
  attribute :type, :string
  attribute :firing_temperature, :integer
end

class CeramicCollection < Lutaml::Model::Serializable
  attribute :featured_piece,
            Ceramic,
            values: [
              Ceramic.new(type: "Porcelain", firing_temperature: 1300),
              Ceramic.new(type: "Stoneware", firing_temperature: 1200),
              Ceramic.new(type: "Earthenware", firing_temperature: 1000),
            ]
end

class GlazeTechnique < Lutaml::Model::Serializable
  attribute :name, :string, values: ["Celadon", "Raku", "Majolica"]
end

RSpec.describe Lutaml::Model::Serializable do
  describe ".model" do
    it "sets the model for the class" do
      expect { described_class.model("Foo") }.to change(described_class, :model)
        .from(nil)
        .to("Foo")
    end
  end

  describe ".attribute" do
    subject(:mapper) { described_class.new }

    it "adds the attribute and getter setter for that attribute" do
      expect do
        described_class.attribute("foo", Lutaml::Model::Type::String)
      end.to change {
               described_class.attributes.keys
             }.from([]).to(["foo"]).and change {
                                          mapper.respond_to?(:foo)
                                        }.from(false).to(true).and change {
                                                                     mapper.respond_to?(:foo=)
                                                                   }.from(false).to(true)
    end
  end

  describe ".hash_representation" do
    context "when model is separate" do
      let(:instance) do
        TestModel.new(name: "John", age: 18)
      end

      let(:expected_hash) do
        {
          "name" => "John",
          "age" => "18",
        }
      end

      it "return hash representation" do
        generate_hash = TestModelMapper.hash_representation(instance, :yaml)
        expect(generate_hash).to eq(expected_hash)
      end
    end

    context "when model is self" do
      let(:instance) do
        TestMapper.new(name: "John", age: 18)
      end

      let(:expected_hash) do
        {
          na: "John",
          ag: "18",
        }
      end

      it "return hash representation" do
        generate_hash = TestMapper.hash_representation(instance, :yaml)
        expect(generate_hash).to eq(expected_hash)
      end
    end
  end

  describe ".mappings_for" do
    context "when mapping is defined" do
      it "returns the defined mapping" do
        actual_mappings = TestMapper.mappings_for(:yaml).mappings

        expect(actual_mappings[0].name).to eq(:na)
        expect(actual_mappings[0].to).to eq(:name)

        expect(actual_mappings[1].name).to eq(:ag)
        expect(actual_mappings[1].to).to eq(:age)
      end
    end

    context "when mapping is not defined" do
      it "maps attributes to mappings" do
        allow(TestMapper.mappings).to receive(:[]).with(:yaml).and_return(nil)

        actual_mappings = TestMapper.mappings_for(:yaml).mappings

        expect(actual_mappings[0].name).to eq("name")
        expect(actual_mappings[0].to).to eq(:name)

        expect(actual_mappings[1].name).to eq("age")
        expect(actual_mappings[1].to).to eq(:age)
      end
    end
  end

  describe ".apply_child_mappings" do
    let(:child_mappings) do
      {
        id: :key,
        path: %i[path link],
        name: %i[path name],
      }
    end

    let(:hash) do
      {
        "foo" => {
          "path" => {
            "link" => "link one",
            "name" => "one",
          },
        },
        "abc" => {
          "path" => {
            "link" => "link two",
            "name" => "two",
          },
        },
        "hello" => {
          "path" => {
            "link" => "link three",
            "name" => "three",
          },
        },
      }
    end

    let(:expected_value) do
      [
        { id: "foo", path: "link one", name: "one" },
        { id: "abc", path: "link two", name: "two" },
        { id: "hello", path: "link three", name: "three" },
      ]
    end

    it "generates hash based on child_mappings" do
      expect(described_class.apply_child_mappings(hash,
                                                  child_mappings)).to eq(expected_value)
    end
  end

  describe "XML root name override" do
    it "uses root name defined at the component class" do
      record_date = RecordDate.new(content: "2021-01-01")
      expected_xml = "<recordDate>2021-01-01</recordDate>"
      expect(record_date.to_xml).to eq(expected_xml)
    end

    it "uses mapped element name at the aggregating class, overriding root name" do
      origin_info = OriginInfo.new(date_issued: [RecordDate.new(content: "2021-01-01")])
      expected_xml = <<~XML
        <originInfo><dateIssued>2021-01-01</dateIssued></originInfo>
      XML
      expect(origin_info.to_xml).to be_equivalent_to(expected_xml)
    end
  end

  describe "String enumeration" do
    context "when assigning an invalid value" do
      it "raises an error after creation" do
        glaze = GlazeTechnique.new(name: "Celadon")
        expect do
          glaze.name = "Tenmoku"
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end

      it "raises an error during creation" do
        expect do
          GlazeTechnique.new(name: "Crystalline")
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end
    end

    context "when assigning a valid value" do
      it "changes the value after creation" do
        glaze = GlazeTechnique.new(name: "Celadon")
        glaze.name = "Raku"
        expect(glaze.name).to eq("Raku")
      end

      it "assigns the value during creation" do
        glaze = GlazeTechnique.new(name: "Majolica")
        expect(glaze.name).to eq("Majolica")
      end
    end
  end

  describe "Serializable object enumeration" do
    context "when assigning an invalid value" do
      it "raises an error after creation" do
        collection = CeramicCollection.new(
          featured_piece: Ceramic.new(type: "Porcelain",
                                      firing_temperature: 1300),
        )
        invalid_ceramic = Ceramic.new(type: "Porcelain",
                                      firing_temperature: 1500)

        expect do
          collection.featured_piece = invalid_ceramic
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end

      it "raises an error during creation" do
        invalid_ceramic = Ceramic.new(type: "Porcelain",
                                      firing_temperature: 1500)
        expect do
          CeramicCollection.new(featured_piece: invalid_ceramic)
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end

      it "raises an error when modifying a nested attribute" do
        collection = CeramicCollection.new(
          featured_piece: Ceramic.new(type: "Porcelain",
                                      firing_temperature: 1300),
        )
        collection.featured_piece.firing_temperature = 1400
        expect do
          collection.validate
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end
    end

    context "when assigning a valid value" do
      it "changes the value after creation" do
        collection = CeramicCollection.new(
          featured_piece: Ceramic.new(type: "Porcelain",
                                      firing_temperature: 1300),
        )
        collection.featured_piece = Ceramic.new(type: "Stoneware",
                                                firing_temperature: 1200)
        expect(collection.featured_piece.type).to eq("Stoneware")
      end

      it "assigns the value during creation" do
        collection = CeramicCollection.new(
          featured_piece: Ceramic.new(type: "Earthenware",
                                      firing_temperature: 1000),
        )
        expect(collection.featured_piece.type).to eq("Earthenware")
      end
    end
  end
end
