# frozen_string_literal: true

module ChildMapping
  class Schema < Lutaml::Model::Serializable
    attribute :id, Lutaml::Model::Type::String
    attribute :path, Lutaml::Model::Type::String
    attribute :name, Lutaml::Model::Type::String
  end

  class ChildMappingClass < Lutaml::Model::Serializable
    attribute :schemas, Schema, collection: true

    json do
      map "schemas", to: :schemas,
                     child_mappings: {
                       id: :key,
                       path: %i[path link],
                       name: %i[path name],
                     }
    end

    yaml do
      map "schemas", to: :schemas,
                     child_mappings: {
                       id: :key,
                       path: %i[path link],
                       name: %i[path name],
                     }
    end

    toml do
      map "schemas", to: :schemas,
                     child_mappings: {
                       id: :key,
                       path: %i[path abc],
                       name: %i[path name],
                     }
    end
  end
end

RSpec.describe ChildMapping do
  let(:mapper) { ChildMapping::ChildMappingClass }
  let(:schema) { ChildMapping::Schema }

  let(:hash) do
    {
      "schemas" => {
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
      },
    }
  end

  let(:expected_ids) { ["foo", "abc", "hello"] }
  let(:expected_paths) { ["link one", "link two", "link three"] }
  let(:expected_names) { ["one", "two", "three"] }

  context "with json" do
    let(:json) do
      hash.to_json
    end

    describe ".from_json" do
      it "create model according to json" do
        instance = mapper.from_json(json)

        expect(instance.schemas.count).to eq(3)
        expect(instance.schemas.map(&:id)).to eq(expected_ids)
        expect(instance.schemas.map(&:path)).to eq(expected_paths)
        expect(instance.schemas.map(&:name)).to eq(expected_names)
      end
    end

    describe ".to_json" do
      it "converts objects to json" do
        schema1 = schema.new(id: "foo", path: "link one", name: "one")
        schema2 = schema.new(id: "abc", path: "link two", name: "two")
        schema3 = schema.new(id: "hello", path: "link three", name: "three")

        instance = mapper.new(schemas: [schema1, schema2, schema3])

        expect(instance.to_json).to eq(json)
      end
    end
  end

  context "with yaml" do
    let(:yaml) do
      hash.to_yaml
    end

    describe ".from_yaml" do
      it "create model according to yaml" do
        instance = mapper.from_yaml(yaml)

        expect(instance.schemas.count).to eq(3)
        expect(instance.schemas.map(&:id)).to eq(expected_ids)
        expect(instance.schemas.map(&:path)).to eq(expected_paths)
        expect(instance.schemas.map(&:name)).to eq(expected_names)
      end
    end

    describe ".to_yaml" do
      it "converts objects to yaml" do
        schema1 = schema.new(id: "foo", path: "link one", name: "one")
        schema2 = schema.new(id: "abc", path: "link two", name: "two")
        schema3 = schema.new(id: "hello", path: "link three", name: "three")

        instance = mapper.new(schemas: [schema1, schema2, schema3])

        expect(instance.to_yaml).to eq(yaml)
      end
    end
  end

  context "with toml" do
    let(:toml) do
      <<~TOML
        [schemas.foo.path]
        abc = "link one"
        name = "one"
        [schemas.abc.path]
        abc = "link two"
        name = "two"
        [schemas.hello.path]
        abc = "link three"
        name = "three"
      TOML
    end

    describe ".from_toml" do
      it "create model according to toml" do
        instance = mapper.from_toml(toml)

        expect(instance.schemas.count).to eq(3)
        expect(instance.schemas.map(&:id)).to eq(expected_ids)
        expect(instance.schemas.map(&:path)).to eq(expected_paths)
        expect(instance.schemas.map(&:name)).to eq(expected_names)
      end
    end

    describe ".to_toml" do
      it "converts objects to toml" do
        schema1 = schema.new(id: "foo", path: "link one", name: "one")
        schema2 = schema.new(id: "abc", path: "link two", name: "two")
        schema3 = schema.new(id: "hello", path: "link three", name: "three")

        instance = mapper.new(schemas: [schema1, schema2, schema3])

        actual = Lutaml::Model::Config.toml_adapter.parse(instance.to_toml)
        expected = Lutaml::Model::Config.toml_adapter.parse(toml)

        expect(actual.attributes).to eq(expected.attributes)
      end
    end
  end
end
