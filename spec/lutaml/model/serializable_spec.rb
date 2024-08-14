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
      expect { described_class.attribute("foo", Lutaml::Model::Type::String) }
        .to change { described_class.attributes.keys }.from([]).to(["foo"])
        .and change { mapper.respond_to?(:foo) }.from(false).to(true)
        .and change { mapper.respond_to?(:foo=) }.from(false).to(true)
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
      expect(described_class.apply_child_mappings(hash, child_mappings))
        .to eq(expected_value)
    end
  end
end
