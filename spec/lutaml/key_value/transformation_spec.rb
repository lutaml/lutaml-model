# frozen_string_literal: true

require "spec_helper"
require "lutaml/key_value/transformation"

RSpec.describe Lutaml::KeyValue::Transformation do
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

        expect(result).to be_a(Hash)
      end

      it "creates proper key-value structure" do
        model = KVSimpleModel.new(name: "John", age: 30, active: true)
        mapping = KVSimpleModel.mappings_for(:json)
        transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

        result = transformation.transform(model)
        expect(result).to eq({
                               "name" => "John",
                               "age" => 30,
                               "active" => true,
                             })
      end

      it "handles nil values based on render_nil" do
        model = KVSimpleModel.new(name: "John", age: nil, active: true)
        mapping = KVSimpleModel.mappings_for(:json)
        transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

        result = transformation.transform(model)
        # nil values should be rendered by default
        expect(result["age"]).to be_nil
      end
    end

    context "with nested model" do
      it "transforms nested model recursively" do
        address = KVAddress.new(street: "123 Main St", city: "NYC",
                                zip: "10001")
        person = KVPerson.new(name: "John", address: address)
        mapping = KVPerson.mappings_for(:json)
        transformation = described_class.new(KVPerson, mapping, :json, nil)

        result = transformation.transform(person)
        expect(result).to eq({
                               "name" => "John",
                               "address" => {
                                 "street" => "123 Main St",
                                 "city" => "NYC",
                                 "zip" => "10001",
                               },
                             })
      end

      it "handles nil nested model" do
        person = KVPerson.new(name: "John", address: nil)
        mapping = KVPerson.mappings_for(:json)
        transformation = described_class.new(KVPerson, mapping, :json, nil)

        result = transformation.transform(person)
        # nil nested model should be in output (based on default render_nil)
        expect(result["address"]).to be_nil
      end
    end

    context "with collections" do
      it "transforms collection to array" do
        team = KVTeam.new(name: "Dev Team",
                          members: ["Alice", "Bob",
                                    "Charlie"])
        mapping = KVTeam.mappings_for(:json)
        transformation = described_class.new(KVTeam, mapping, :json, nil)

        result = transformation.transform(team)
        expect(result).to eq({
                               "name" => "Dev Team",
                               "members" => ["Alice", "Bob",
                                             "Charlie"],
                             })
      end

      it "handles empty collection" do
        team = KVTeam.new(name: "Dev Team", members: [])
        mapping = KVTeam.mappings_for(:json)
        transformation = described_class.new(KVTeam, mapping, :json, nil)

        result = transformation.transform(team)
        # Empty collections are not rendered by default (render_empty defaults to false)
        expect(result["members"]).to be_nil
      end

      it "handles nil collection" do
        team = KVTeam.new(name: "Dev Team", members: nil)
        mapping = KVTeam.mappings_for(:json)
        transformation = described_class.new(KVTeam, mapping, :json, nil)

        result = transformation.transform(team)
        # nil collection should be nil by default
        expect(result["members"]).to be_nil
      end
    end

    context "with value transformations" do
      class KVTransformModel < Lutaml::Model::Serializable
        attribute :name, :string

        json do
          map "name", to: :name, transform: {
            export: lambda(&:upcase),
            import: lambda(&:downcase),
          }
        end
      end

      it "applies export transformation" do
        model = KVTransformModel.new(name: "john")
        mapping = KVTransformModel.mappings_for(:json)
        transformation = described_class.new(KVTransformModel, mapping, :json,
                                             nil)

        result = transformation.transform(model)
        expect(result["name"]).to eq("JOHN")
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
        # optional should be omitted
        expect(result.keys).not_to include("optional")
      end

      it "omits default values when render_default: false" do
        model = KVRenderModel.new # Uses default
        mapping = KVRenderModel.mappings_for(:json)
        transformation = described_class.new(KVRenderModel, mapping, :json, nil)

        result = transformation.transform(model)
        # defaulted should be omitted
        expect(result.keys).not_to include("defaulted")
      end
    end
  end

  describe "architecture compliance" do
    it "emits the presentation hash directly (TODO.perf 19)" do
      model = KVSimpleModel.new(name: "John", age: 30, active: true)
      mapping = KVSimpleModel.mappings_for(:json)
      transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

      result = transformation.transform(model)

      expect(result).to be_a(Hash)
      expect(result).to eq("name" => "John", "age" => 30, "active" => true)
    end

    it "separates content (KeyValueElement) from presentation (Hash)" do
      skip "superseded by hash-direct emission (TODO.perf 19)"
      model = KVSimpleModel.new(name: "John", age: 30, active: true)
      mapping = KVSimpleModel.mappings_for(:json)
      transformation = described_class.new(KVSimpleModel, mapping, :json, nil)

      # Transformation produces content model
      result = transformation.transform(model)
      expect(result).to be_a(Lutaml::KeyValue::DataModel::Element)

      # Presentation happens via to_hash, not during transformation
      expect(hash).to be_a(Hash)
    end
  end

  describe "immutability" do
    class FrozenLazyTransformation < described_class
      private

      def compile_rules(_mapping_dsl)
        []
      end
    end

    it "does not lazily initialize collaborators after freeze" do
      transformation = FrozenLazyTransformation.new(
        KVSimpleModel,
        KVSimpleModel.mappings_for(:json),
        :json,
        nil,
      )

      expect(transformation).to be_frozen

      rule = Lutaml::Model::CompiledRule.new(
        attribute_name: :name,
        serialized_name: "name",
      )
      expect do
        transformation.send(:valid_mapping?, rule, {})
      end.not_to raise_error
    end
  end

  describe "custom to: methods under hash-direct emission (pubid regression)" do
    before do
      stub_const("PubidRegress", Module.new)
      stub_const("PubidRegress::EmptyCustom", empty_custom_class)
      stub_const("PubidRegress::ValueWriter", value_writer_class)
      stub_const("PubidRegress::ReturnOnly", return_only_class)
    end

    let(:empty_custom_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :code, :string
        key_value do
          map "code", to: :code, with: { to: :to_code }
        end

        # pubid 2.0's shape: inspects the doc and may return without
        # writing anything — must not crash the emission.
        def to_code(_model, doc); end
      end
    end

    let(:value_writer_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :code, :string
        key_value do
          map "code", to: :code, with: { to: :to_code }
        end

        def to_code(model, doc)
          doc.value["code"] = model.code
        end
      end
    end

    let(:return_only_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :code, :string
        key_value do
          map "code", to: :code, with: { to: :to_code }
        end

        # Returns its value without touching the doc — a shape the
        # mutation-only contract must serialize as nothing (#892).
        def to_code(_model, _doc)
          { "code" => "RETURNED" }
        end
      end
    end

    it "tolerates a custom method that writes nothing to the doc" do
      model = PubidRegress::EmptyCustom.new(code: "X")
      expect(model.to_hash).to eq({})
    end

    it "merges a custom method writing through doc.value" do
      model = PubidRegress::ValueWriter.new(code: "X")
      expect(model.to_hash).to eq("code" => "X")
    end

    it "builds nested structures through chained Element writes" do
      # glossarist's Citation#locality_to_yaml pattern: assign an empty
      # hash child, then write into it through the hash-like reader —
      # the reader must return the child's own value object.
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :type, :string
        attribute :reference_from, :string

        key_value do
          map "locality", to: :type, with: { to: :locality_to_yaml }
        end

        def locality_to_yaml(model, doc)
          doc["locality"] = {}
          doc["locality"]["type"] = model.type
          doc["locality"]["reference_from"] = model.reference_from
        end
      end

      model = klass.new(type: "clause", reference_from: "§3")
      expect(model.to_hash).to eq(
        "locality" => { "type" => "clause", "reference_from" => "§3" },
      )
    end

    it "ignores a custom method's return value (mutation-only contract)" do
      # A method returning a hash without touching the doc serializes
      # as nothing — honoring returns merged child content at the
      # wrong level (lutaml-model#892).
      model = PubidRegress::ReturnOnly.new(code: "X")
      expect(model.to_hash).to eq({})
    end
  end
end
