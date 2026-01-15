# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/key_value/transformation"

RSpec.describe Lutaml::Model::KeyValue::Transformation do
  # Simple model for testing
  class KVSimpleModel < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :age, :integer
    attribute :active, :boolean

    json do
      map "name", to: :name
      map "age", to: :age
      map "active", to: :active
    end
  end

  # Nested model for testing
  class KVAddress < Lutaml::Model::Serializable
    attribute :street, :string
    attribute :city, :string
    attribute :zip, :string

    json do
      map "street", to: :street
      map "city", to: :city
      map "zip", to: :zip
    end
  end

  class KVPerson < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :address, KVAddress

    json do
      map "name", to: :name
      map "address", to: :address
    end
  end

  # Collection model for testing
  class KVTeam < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :members, :string, collection: true

    json do
      map "name", to: :name
      map "members", to: :members
    end
  end

  describe "#transform" do
    context "with simple model" do
      it "transforms model to KeyValueElement tree" do
        model = KVSimpleModel.new(name: "John", age: 30, active: true)
        mapping = KVSimpleModel.mappings_for(:json)
        transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

        result = transformation.transform(model)

        expect(result).to be_a(Lutaml::Model::KeyValueDataModel::KeyValueElement)
        expect(result.key).to eq("__root__")
        expect(result.children.length).to eq(3)
      end

      it "creates proper key-value structure" do
        model = KVSimpleModel.new(name: "John", age: 30, active: true)
        mapping = KVSimpleModel.mappings_for(:json)
        transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

        result = transformation.transform(model)
        hash = result.to_hash

        # Remove __root__ wrapper
        expect(hash["__root__"]).to eq({
          "name" => "John",
          "age" => 30,
          "active" => true
        })
      end

      it "handles nil values based on render_nil" do
        model = KVSimpleModel.new(name: "John", age: nil, active: true)
        mapping = KVSimpleModel.mappings_for(:json)
        transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

        result = transformation.transform(model)
        hash = result.to_hash

        # nil values should be rendered by default
        expect(hash["__root__"]["age"]).to be_nil
      end
    end

    context "with nested model" do
      it "transforms nested model recursively" do
        address = KVAddress.new(street: "123 Main St", city: "NYC", zip: "10001")
        person = KVPerson.new(name: "John", address: address)
        mapping = KVPerson.mappings_for(:json)
        transformation = described_class.new(KVPerson, mapping, :json, nil)

        result = transformation.transform(person)
        hash = result.to_hash

        expect(hash["__root__"]).to eq({
          "name" => "John",
          "address" => {
            "street" => "123 Main St",
            "city" => "NYC",
            "zip" => "10001"
          }
        })
      end

      it "handles nil nested model" do
        person = KVPerson.new(name: "John", address: nil)
        mapping = KVPerson.mappings_for(:json)
        transformation = described_class.new(KVPerson, mapping, :json, nil)

        result = transformation.transform(person)
        hash = result.to_hash

        # nil nested model should be in output (based on default render_nil)
        expect(hash["__root__"]["address"]).to be_nil
      end
    end

    context "with collections" do
      it "transforms collection to array" do
        team = KVTeam.new(name: "Dev Team", members: ["Alice", "Bob", "Charlie"])
        mapping = KVTeam.mappings_for(:json)
        transformation = described_class.new(KVTeam, mapping, :json, nil)

        result = transformation.transform(team)
        hash = result.to_hash

        expect(hash["__root__"]).to eq({
          "name" => "Dev Team",
          "members" => ["Alice", "Bob", "Charlie"]
        })
      end

      it "handles empty collection" do
        team = KVTeam.new(name: "Dev Team", members: [])
        mapping = KVTeam.mappings_for(:json)
        transformation = described_class.new(KVTeam, mapping, :json, nil)

        result = transformation.transform(team)
        hash = result.to_hash

        # Empty collections are not rendered by default (render_empty defaults to false)
        expect(hash["__root__"]["members"]).to be_nil
      end

      it "handles nil collection" do
        team = KVTeam.new(name: "Dev Team", members: nil)
        mapping = KVTeam.mappings_for(:json)
        transformation = described_class.new(KVTeam, mapping, :json, nil)

        result = transformation.transform(team)
        hash = result.to_hash

        # nil collection should be nil by default
        expect(hash["__root__"]["members"]).to be_nil
      end
    end

    context "with value transformations" do
      class KVTransformModel < Lutaml::Model::Serializable
        attribute :name, :string

        json do
          map "name", to: :name, transform: {
            export: ->(v) { v.upcase },
            import: ->(v) { v.downcase }
          }
        end
      end

      it "applies export transformation" do
        model = KVTransformModel.new(name: "john")
        mapping = KVTransformModel.mappings_for(:json)
        transformation = described_class.new(KVTransformModel, mapping, :json, nil)

        result = transformation.transform(model)
        hash = result.to_hash

        expect(hash["__root__"]["name"]).to eq("JOHN")
      end
    end

    context "with render options" do
      class KVRenderModel < Lutaml::Model::Serializable
        attribute :optional, :string
        attribute :defaulted, :string, default: -> { "default" }

        json do
          map "optional", to: :optional, render_nil: :omit
          map "defaulted", to: :defaulted, render_default: false
        end
      end

      it "omits nil values when render_nil: :omit" do
        model = KVRenderModel.new(optional: nil)
        mapping = KVRenderModel.mappings_for(:json)
        transformation = described_class.new(KVRenderModel, mapping, :json, nil)

        result = transformation.transform(model)
        hash = result.to_hash

        # optional should be omitted
        expect(hash["__root__"].keys).not_to include("optional")
      end

      it "omits default values when render_default: false" do
        model = KVRenderModel.new  # Uses default
        mapping = KVRenderModel.mappings_for(:json)
        transformation = described_class.new(KVRenderModel, mapping, :json, nil)

        result = transformation.transform(model)
        hash = result.to_hash

        # defaulted should be omitted
        expect(hash["__root__"].keys).not_to include("defaulted")
      end
    end
  end

  describe "architecture compliance" do
    it "produces OOP data structures, not raw hashes" do
      model = KVSimpleModel.new(name: "John", age: 30, active: true)
      mapping = KVSimpleModel.mappings_for(:json)
      transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

      result = transformation.transform(model)

      # Result should be KeyValueElement, not Hash
      expect(result).to be_a(Lutaml::Model::KeyValueDataModel::KeyValueElement)
      expect(result).not_to be_a(Hash)

      # Children should also be KeyValueElements
      expect(result.children).to all(be_a(Lutaml::Model::KeyValueDataModel::KeyValueElement))
    end

    it "separates content (KeyValueElement) from presentation (Hash)" do
      model = KVSimpleModel.new(name: "John", age: 30, active: true)
      mapping = KVSimpleModel.mappings_for(:json)
      transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

      # Transformation produces content model
      result = transformation.transform(model)
      expect(result).to be_a(Lutaml::Model::KeyValueDataModel::KeyValueElement)

      # Presentation happens via to_hash, not during transformation
      hash = result.to_hash
      expect(hash).to be_a(Hash)
    end
  end
end