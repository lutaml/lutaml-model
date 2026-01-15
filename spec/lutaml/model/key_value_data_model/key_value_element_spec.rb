# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/key_value_data_model"

RSpec.describe Lutaml::Model::KeyValueDataModel::KeyValueElement do
  describe "#initialize" do
    it "creates element with key and no value" do
      element = described_class.new("name")
      expect(element.key).to eq("name")
      expect(element.value).to be_nil
      expect(element.children).to be_empty
    end

    it "creates element with key and value" do
      element = described_class.new("name", "John")
      expect(element.key).to eq("name")
      expect(element.value).to eq("John")
      expect(element.children).to be_empty
    end

    it "converts symbol key to string" do
      element = described_class.new(:name, "John")
      expect(element.key).to eq("name")
    end
  end

  describe "#add_child" do
    let(:element) { described_class.new("person") }

    it "adds a child element" do
      child = described_class.new("name", "John")
      element.add_child(child)

      expect(element.children).to contain_exactly(child)
    end

    it "adds multiple children" do
      child1 = described_class.new("name", "John")
      child2 = described_class.new("age", 30)

      element.add_child(child1)
      element.add_child(child2)

      expect(element.children).to contain_exactly(child1, child2)
    end

    it "adds primitive values as children" do
      element.add_child("apple")
      element.add_child("banana")

      expect(element.children).to eq(["apple", "banana"])
    end

    it "returns self for chaining" do
      child = described_class.new("name", "John")
      result = element.add_child(child)

      expect(result).to eq(element)
    end
  end

  describe "#has_children?" do
    it "returns false for element without children" do
      element = described_class.new("name", "John")
      expect(element).not_to have_children
    end

    it "returns true for element with children" do
      element = described_class.new("person")
      element.add_child(described_class.new("name", "John"))

      expect(element).to have_children
    end
  end

  describe "#has_value?" do
    it "returns false for element without value" do
      element = described_class.new("person")
      expect(element).not_to have_value
    end

    it "returns true for element with value" do
      element = described_class.new("name", "John")
      expect(element).to have_value
    end

    it "returns false for nil value" do
      element = described_class.new("name", nil)
      expect(element).not_to have_value
    end
  end

  describe "#leaf?" do
    it "returns true for element with value and no children" do
      element = described_class.new("name", "John")
      expect(element).to be_leaf
    end

    it "returns false for element with children" do
      element = described_class.new("person")
      element.add_child(described_class.new("name", "John"))

      expect(element).not_to be_leaf
    end

    it "returns false for element without value" do
      element = described_class.new("person")
      expect(element).not_to be_leaf
    end
  end

  describe "#to_hash" do
    context "with simple value" do
      it "returns hash with key-value pair" do
        element = described_class.new("name", "John")
        expect(element.to_hash).to eq({ "name" => "John" })
      end

      it "handles integer values" do
        element = described_class.new("age", 30)
        expect(element.to_hash).to eq({ "age" => 30 })
      end

      it "handles boolean values" do
        element = described_class.new("active", true)
        expect(element.to_hash).to eq({ "active" => true })
      end

      it "handles nil value" do
        element = described_class.new("middle_name")
        expect(element.to_hash).to eq({ "middle_name" => nil })
      end
    end

    context "with nested KeyValueElement children" do
      it "creates nested hash structure" do
        person = described_class.new("person")
        person.add_child(described_class.new("name", "John"))
        person.add_child(described_class.new("age", 30))

        expected = {
          "person" => {
            "name" => "John",
            "age" => 30
          }
        }

        expect(person.to_hash).to eq(expected)
      end

      it "handles deeply nested structures" do
        root = described_class.new("root")
        person = described_class.new("person")
        address = described_class.new("address")

        address.add_child(described_class.new("city", "NYC"))
        address.add_child(described_class.new("zip", "10001"))

        person.add_child(described_class.new("name", "John"))
        person.add_child(address)

        root.add_child(person)

        expected = {
          "root" => {
            "person" => {
              "name" => "John",
              "address" => {
                "city" => "NYC",
                "zip" => "10001"
              }
            }
          }
        }

        expect(root.to_hash).to eq(expected)
      end
    end

    context "with primitive array children" do
      it "creates array from primitive values" do
        items = described_class.new("items")
        items.add_child("apple")
        items.add_child("banana")
        items.add_child("orange")

        expect(items.to_hash).to eq({ "items" => ["apple", "banana", "orange"] })
      end

      it "handles numeric arrays" do
        numbers = described_class.new("numbers")
        numbers.add_child(1)
        numbers.add_child(2)
        numbers.add_child(3)

        expect(numbers.to_hash).to eq({ "numbers" => [1, 2, 3] })
      end

      it "handles mixed type arrays" do
        values = described_class.new("values")
        values.add_child("text")
        values.add_child(42)
        values.add_child(true)

        expect(values.to_hash).to eq({ "values" => ["text", 42, true] })
      end
    end

    context "with mixed children (KeyValueElements and primitives)" do
      it "converts to array with extracted values" do
        mixed = described_class.new("mixed")
        mixed.add_child(described_class.new("item1", "value1"))
        mixed.add_child("primitive")
        mixed.add_child(described_class.new("item2", "value2"))

        expect(mixed.to_hash).to eq({
          "mixed" => ["value1", "primitive", "value2"]
        })
      end
    end

    context "with value and children" do
      it "prioritizes children over direct value" do
        element = described_class.new("person", "ignored")
        element.add_child(described_class.new("name", "John"))

        expect(element.to_hash).to eq({
          "person" => { "name" => "John" }
        })
      end
    end
  end

  describe "#to_s and #inspect" do
    it "shows key and value for leaf nodes" do
      element = described_class.new("name", "John")
      expect(element.to_s).to include("name")
      expect(element.to_s).to include("John")
    end

    it "shows key and children count for parent nodes" do
      element = described_class.new("person")
      element.add_child(described_class.new("name", "John"))
      element.add_child(described_class.new("age", 30))

      expect(element.to_s).to include("person")
      expect(element.to_s).to include("children=2")
    end

    it "inspect returns same as to_s" do
      element = described_class.new("name", "John")
      expect(element.inspect).to eq(element.to_s)
    end
  end

  describe "real-world usage examples" do
    it "models JSON structure" do
      # JSON: {"user": {"name": "John", "emails": ["john@example.com", "j@example.com"]}}
      user = described_class.new("user")
      user.add_child(described_class.new("name", "John"))

      emails = described_class.new("emails")
      emails.add_child("john@example.com")
      emails.add_child("j@example.com")

      user.add_child(emails)

      expected = {
        "user" => {
          "name" => "John",
          "emails" => ["john@example.com", "j@example.com"]
        }
      }

      expect(user.to_hash).to eq(expected)
    end

    it "models YAML structure with nested objects" do
      # YAML:
      # database:
      #   adapter: postgresql
      #   pool: 5
      #   timeout: 5000
      database = described_class.new("database")
      database.add_child(described_class.new("adapter", "postgresql"))
      database.add_child(described_class.new("pool", 5))
      database.add_child(described_class.new("timeout", 5000))

      expected = {
        "database" => {
          "adapter" => "postgresql",
          "pool" => 5,
          "timeout" => 5000
        }
      }

      expect(database.to_hash).to eq(expected)
    end

    it "models array of objects" do
      # JSON: {"users": [{"name": "John"}, {"name": "Jane"}]}
      users = described_class.new("users")

      # For array of objects, add the hash representations directly as primitives
      # This correctly models JSON/YAML array structures
      users.add_child({ "name" => "John" })
      users.add_child({ "name" => "Jane" })

      result = users.to_hash
      expect(result["users"]).to be_an(Array)
      expect(result["users"]).to contain_exactly(
        { "name" => "John" },
        { "name" => "Jane" }
      )
    end
  end
end