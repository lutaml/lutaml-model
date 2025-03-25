require "spec_helper"

RSpec.describe "HashAdapter" do
  before do
    stub_const("HashMappingSpec", Module.new)

    simple_class = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer
      attribute :active, :boolean

      hsh do
        map "name", to: :name
        map "age", to: :age
        map "is_active", to: :active
      end
    end

    stub_const("HashMappingSpec::SimpleClass", simple_class)

    nested_class = Class.new(Lutaml::Model::Serializable) do
      attribute :title, :string
      attribute :simple, HashMappingSpec::SimpleClass
      attribute :items, :string, collection: true

      hsh do
        map "title", to: :title
        map "simple", to: :simple
        map "items", to: :items
      end
    end

    stub_const("HashMappingSpec::NestedClass", nested_class)

    collection_class = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :simples, HashMappingSpec::SimpleClass, collection: true

      hsh do
        map "name", to: :name
        map "simples", to: :simples
      end
    end

    stub_const("HashMappingSpec::CollectionClass", collection_class)
  end

  describe "from_hash" do
    context "with simple attributes" do
      let(:parsed) do
        HashMappingSpec::SimpleClass.from_hash(hash_data)
      end

      let(:hash_data) do
        {
          "name" => "John Doe",
          "age" => 30,
          "is_active" => true,
        }
      end

      let(:expected) do
        HashMappingSpec::SimpleClass.new(
          name: "John Doe",
          age: 30,
          active: true,
        )
      end

      it "deserializes hash to object" do
        expect(parsed).to eq(expected)
      end
    end

    context "with nested objects" do
      let(:parsed) do
        HashMappingSpec::NestedClass.from_hash(hash_data)
      end

      let(:hash_data) do
        {
          "title" => "Test Title",
          "simple" => {
            "name" => "Jane Doe",
            "age" => 25,
            "is_active" => false,
          },
          "items" => ["item1", "item2", "item3"],
        }
      end

      let(:expected) do
        HashMappingSpec::NestedClass.new(
          title: "Test Title",
          simple: HashMappingSpec::SimpleClass.new(
            name: "Jane Doe",
            age: 25,
            active: false,
          ),
          items: ["item1", "item2", "item3"],
        )
      end

      it "deserializes nested objects" do
        expect(parsed).to eq(expected)
      end
    end

    context "with collections of objects" do
      let(:parsed) do
        HashMappingSpec::CollectionClass.from_hash(hash_data)
      end

      let(:hash_data) do
        {
          "name" => "Collection",
          "simples" => [
            { "name" => "First", "age" => 10, "is_active" => true },
            { "name" => "Second", "age" => 20, "is_active" => false },
          ],
        }
      end

      let(:expected) do
        HashMappingSpec::CollectionClass.new(
          name: "Collection",
          simples: [
            HashMappingSpec::SimpleClass.new(
              name: "First",
              age: 10,
              active: true,
            ),
            HashMappingSpec::SimpleClass.new(
              name: "Second",
              age: 20,
              active: false,
            ),
          ],
        )
      end

      it "deserializes collections of objects" do
        expect(parsed).to eq(expected)
      end
    end
  end

  describe "to_hash" do
    context "with simple attributes" do
      let(:instance) do
        HashMappingSpec::SimpleClass.new(
          name: "John Doe",
          age: 30,
          active: true,
        )
      end

      let(:expected_hash) do
        {
          "name" => "John Doe",
          "age" => 30,
          "is_active" => true,
        }
      end

      it "serializes object to hash" do
        expect(instance.to_hash).to eq(expected_hash)
      end
    end

    context "with nested objects" do
      let(:simple) do
        HashMappingSpec::SimpleClass.new(
          name: "Jane Doe",
          age: 25,
          active: false,
        )
      end

      let(:instance) do
        HashMappingSpec::NestedClass.new(
          title: "Test Title",
          simple: simple,
          items: ["item1", "item2", "item3"],
        )
      end

      let(:expected_hash) do
        {
          "title" => "Test Title",
          "simple" => {
            "name" => "Jane Doe",
            "age" => 25,
            "is_active" => false,
          },
          "items" => ["item1", "item2", "item3"],
        }
      end

      it "serializes nested objects to hash" do
        expect(instance.to_hash).to eq(expected_hash)
      end
    end

    context "with collections of objects" do
      let(:simples) do
        [
          HashMappingSpec::SimpleClass.new(name: "First", age: 10, active: true),
          HashMappingSpec::SimpleClass.new(name: "Second", age: 20, active: false),
        ]
      end

      let(:instance) do
        HashMappingSpec::CollectionClass.new(
          name: "Collection",
          simples: simples,
        )
      end

      let(:expected_hash) do
        {
          "name" => "Collection",
          "simples" => [
            { "name" => "First", "age" => 10, "is_active" => true },
            { "name" => "Second", "age" => 20, "is_active" => false },
          ],
        }
      end

      it "serializes collections of objects to hash" do
        expect(instance.to_hash).to eq(expected_hash)
      end
    end
  end

  describe "round-trip serialization" do
    let(:original_hash) do
      {
        "name" => "Collection",
        "simples" => [
          { "name" => "First", "age" => 10, "is_active" => true },
          { "name" => "Second", "age" => 20, "is_active" => false },
        ],
      }
    end

    let(:parsed) do
      HashMappingSpec::CollectionClass.from_hash(original_hash)
    end

    it "maintains data integrity through serialization and deserialization" do
      expect(parsed.to_hash).to eq(original_hash)
    end
  end
end
