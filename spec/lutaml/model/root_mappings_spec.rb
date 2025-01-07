module RootMapping
  class Power < Lutaml::Model::Serializable
    attribute :power_denominator, :integer
    attribute :power_numerator, :integer

    key_value do
      map :power_denominator, to: :power_denominator
      map :power_numerator, to: :power_numerator
    end
  end

  class EnumeratedRootUnit < Lutaml::Model::Serializable
    attribute :unit, :string
    attribute :power, Power

    key_value do
      map :unit, to: :unit
      map :power, to: :power
    end
  end

  class RootUnit < Lutaml::Model::Serializable
    attribute :enumerated_root_unit, EnumeratedRootUnit

    key_value do
      map :enumerated_root_units, to: :enumerated_root_unit
    end
  end

  class Unit < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :root_unit, RootUnit
  end

  class UnitsDb < Lutaml::Model::Serializable
    attribute :root_unit, Unit, collection: true

    key_value do
      map to: :root_unit, root_mappings: { id: :key, root_unit: :root_units }
    end
  end

  class Person < Lutaml::Model::Serializable
    attribute :id, :integer
    attribute :email, :string

    key_value do
      map :id, to: :id
      map :email, to: :email
    end
  end

  class RootMappingWithoutNesting < Lutaml::Model::Serializable
    attribute :person, Person, collection: true

    key_value do
      map to: :person, root_mappings: { id: :key, email: :value }
    end
  end

  class Path < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :path, :string

    key_value do
      map :id, to: :id
      map :path, to: :path
    end
  end

  class RootMappingWithoutClasses < Lutaml::Model::Serializable
    attribute :path, Path, collection: true

    key_value do
      map to: :path, root_mappings: { id: :key, path: %w[root_units enumerated_root_units] }
    end
  end

  class CollectionTrueMissing < Lutaml::Model::Serializable
    attribute :path, Path

    key_value do
      map to: :path, root_mappings: { id: :key, path: %w[root_units enumerated_root_units] }
    end
  end

  class Ceramic < Lutaml::Model::Serializable
    attribute :ceramic_id, :string
    attribute :ceramic_name, :string

    key_value do
      map "id", to: :ceramic_id
      map "ceramic_name", to: :ceramic_name
    end
  end

  class CeramicCollection < Lutaml::Model::Serializable
    attribute :ceramics, Ceramic, collection: true

    key_value do
      map to: :ceramics, root_mappings: { ceramic_id: :key }
    end
  end
end

RSpec.describe RootMapping do
  let(:mapper) { RootMapping::UnitsDb }

  let(:ceramic_hash) do
    {
      "vase1" => {
        "name" => "Imperial Vase",
      },
      "bowl2" => {
        "name" => "18th Century Bowl",
      },
    }
  end

  let(:simple_hash) do
    {
      2 => "a@gmail.com",
      1 => "b@gmail.com",
      4 => "c@gmail.com",
    }
  end

  let(:hash) do
    {
      "NISTu1" => {
        "root_units" => {
          "enumerated_root_units" => {
            "unit" => "meter",
            "power" => {
              "power_denominator" => 1,
              "power_numerator" => 1,
            },
          },
        },
      },
      "NISTu2" => {
        "root_units" => {
          "enumerated_root_units" => {
            "unit" => "inches",
            "power" => {
              "power_denominator" => 2,
              "power_numerator" => 7,
            },
          },
        },
      },
    }
  end

  let(:hash_with_known_key) do
    {
      "NISTu1" => {
        "root_units" => {
          "enumerated_root_units" => "meter",
        },
      },
      "NISTu2" => {
        "root_units" => {
          "enumerated_root_units" => "inches",
        },
      },
    }
  end

  let(:hash_with_multiple_values) do
    {
      "u1" => {
        "check" => "meter",
      },
      "u2" => {
        "check" => "inches",
      },
    }
  end

  context "with yaml" do
    let(:yaml) do
      hash.to_yaml
    end

    let(:simple_yaml) do
      simple_hash.to_yaml
    end

    let(:yaml_data) do
      hash_with_known_key.to_yaml
    end

    describe ".from_yaml" do
      it "create model according to yaml" do
        instance = mapper.from_yaml(yaml)

        expect(instance.root_unit.first.id).to eq("NISTu1")
      end

      it "creates model without defining nesting elements" do
        instance = RootMapping::RootMappingWithoutNesting.from_yaml(simple_yaml)

        expect(instance.person.first.id).to eq(2)
        expect(instance.person.first.email).to eq("a@gmail.com")
      end

      it "creates model without defining classes for nesting elements" do
        instance = RootMapping::RootMappingWithoutClasses.from_yaml(yaml_data)

        expect(instance.path.first.id).to eq("NISTu1")
        expect(instance.path.first.path).to eq("meter")
        expect(instance.path[1].id).to eq("NISTu2")
        expect(instance.path[1].path).to eq("inches")
      end

      it "creates yaml with collection" do
        ceramic_collection = RootMapping::CeramicCollection.from_yaml(ceramic_hash.to_yaml)

        expect(ceramic_collection.ceramics.first.ceramic_id).to eq("vase1")
        expect(ceramic_collection.ceramics.last.ceramic_id).to eq("bowl2")
      end
    end

    describe ".to_yaml" do
      it "converts objects to yaml" do
        instance = mapper.from_yaml(yaml)
        serialized = instance.to_yaml

        expect(YAML.safe_load(serialized)).to eq(YAML.safe_load(yaml))
      end

      it "serializes data without defining nesting elements" do
        instance = RootMapping::RootMappingWithoutNesting.from_yaml(simple_yaml)
        serialized = instance.to_yaml

        expect(YAML.safe_load(serialized)).to eq(YAML.safe_load(simple_yaml))
      end

      it "serializes data without defining classes for nesting elements" do
        instance = RootMapping::RootMappingWithoutClasses.from_yaml(yaml_data)
        serialized = instance.to_yaml

        expect(serialized).to eq(yaml_data)
      end
    end
  end

  context "with yaml for ceramic collection class" do
    let(:instance) do
      RootMapping::CeramicCollection.new(ceramics: [
                                           RootMapping::Ceramic.new(ceramic_id: "vase1", ceramic_name: "Imperial Vase"),
                                           RootMapping::Ceramic.new(ceramic_id: "bowl2", ceramic_name: "18th Century Bowl"),
                                         ])
    end

    it "serializes first instance from collection into yaml" do
      expect(instance.ceramics.first.to_yaml).to eq("---\nid: vase1\nceramic_name: Imperial Vase\n")
    end

    it "serializes instance having collection into yaml" do
      expect(instance.to_yaml).to eq({ "vase1" => nil, "bowl2" => nil }.to_yaml)
    end
  end

  context "with json" do
    let(:json) do
      hash.to_json
    end

    let(:simple_json) do
      simple_hash.to_json
    end

    let(:json_data) do
      hash_with_known_key.to_json
    end

    describe ".from_json" do
      it "create model according to yaml" do
        instance = mapper.from_json(json)

        expect(instance.root_unit.first.id).to eq("NISTu1")
      end

      it "creates model without defining nesting elements" do
        instance = RootMapping::RootMappingWithoutNesting.from_json(simple_json)

        expect(instance.person.first.id).to eq(2)
        expect(instance.person.first.email).to eq("a@gmail.com")
      end

      it "creates model without defining classes for nesting elements" do
        instance = RootMapping::RootMappingWithoutClasses.from_json(json_data)

        expect(instance.path.first.id).to eq("NISTu1")
        expect(instance.path.first.path).to eq("meter")
        expect(instance.path[1].id).to eq("NISTu2")
        expect(instance.path[1].path).to eq("inches")
      end
    end

    describe ".to_json" do
      it "converts objects to json" do
        instance = mapper.from_json(json)
        serialized = instance.to_json

        expect(serialized).to eq(json)
      end

      it "serializes data without defining nesting elements" do
        instance = RootMapping::RootMappingWithoutNesting.from_json(simple_json)
        serialized = instance.to_json

        expect(serialized).to eq(simple_json)
      end

      it "serializes data without defining classes for nesting elements" do
        instance = RootMapping::RootMappingWithoutClasses.from_json(json_data)
        serialized = instance.to_json

        expect(serialized).to eq(json_data)
      end
    end
  end

  context "when root_mappings are defined with other mappings" do
    it "raises error" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string
          attribute :name, :string
          attribute :unit, :string

          key_value do
            map to: :unit, root_mappings: { id: :key, unit: :value }
            map :name, to: :name
            map :id, to: :id
          end
        end
      end.to raise_error(Lutaml::Model::MultipleMappingsError, "root_mappings cannot be used with other mappings")
    end

    it "raises error with different order" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string
          attribute :name, :string
          attribute :unit, :string

          key_value do
            map :name, to: :name
            map :id, to: :id
            map to: :unit, root_mappings: { id: :key, unit: :value }
          end
        end
      end.to raise_error(Lutaml::Model::MultipleMappingsError, "root_mappings cannot be used with other mappings")
    end
  end

  it "raises error when collection true is missing" do
    expect do
      RootMapping::CollectionTrueMissing.from_yaml(hash_with_multiple_values.to_yaml)
    end.to raise_error(
      Lutaml::Model::CollectionTrueMissingError,
      "May be `collection: true` is missing for `path` in RootMapping::CollectionTrueMissing",
    )
  end
end
