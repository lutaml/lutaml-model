# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::KeyValue::Transformation::CollectionSerializer do
  let(:format) { :json }
  let(:register_id) { :default }

  let(:value_serializer) do
    instance_double(Lutaml::KeyValue::Transformation::ValueSerializer).tap do |vs|
      allow(vs).to receive(:serialize_item) do |value, _rule, _options|
        value
      end
    end
  end

  let(:transformation_factory) do
    ->(type_class) do
      double("Transformation", transform: double("Element", to_hash: { "__root__" => { "name" => "test" } }))
    end
  end

  let(:serializer) do
    described_class.new(
      format: format,
      register_id: register_id,
      value_serializer: value_serializer,
      transformation_factory: transformation_factory
    )
  end

  describe "#initialize" do
    it "stores format" do
      expect(serializer.format).to eq(:json)
    end

    it "stores register_id" do
      expect(serializer.register_id).to eq(:default)
    end

    it "stores value_serializer" do
      expect(serializer.value_serializer).to eq(value_serializer)
    end

    it "stores transformation_factory" do
      expect(serializer.transformation_factory).to eq(transformation_factory)
    end
  end

  describe "#keyed_collection_key_attribute" do
    it "returns nil for nil child_mappings" do
      expect(serializer.keyed_collection_key_attribute(nil)).to be_nil
    end

    it "returns the key attribute when present" do
      child_mappings = { id: :key, name: :value }
      expect(serializer.keyed_collection_key_attribute(child_mappings)).to eq(:id)
    end

    it "returns nil when no :key mapping" do
      child_mappings = { name: :value }
      expect(serializer.keyed_collection_key_attribute(child_mappings)).to be_nil
    end
  end

  describe "#serialize" do
    let(:parent) { Lutaml::KeyValue::DataModel::Element.new("root") }
    let(:rule) { build_rule(is_collection: true) }

    context "with nil collection" do
      it "skips nil collection by default" do
        # Stub render_nil? to return false (default behavior is to skip nil)
        allow(rule).to receive(:option).with(:render_nil).and_return(nil)
        allow(rule).to receive(:option).with(:value_map).and_return({ to: { nil: :omit } })
        serializer.serialize(parent, nil, rule)
        expect(parent.children).to be_empty
      end

      it "renders nil when render_nil is true" do
        allow(rule).to receive(:option).with(:render_nil).and_return(true)
        allow(rule).to receive(:option).with(:value_map).and_return({})
        serializer.serialize(parent, nil, rule)
        expect(parent.children).not_to be_empty
        expect(parent.children.first.value).to be_nil
      end

      it "renders empty array when render_nil is :as_empty" do
        allow(rule).to receive(:option).with(:render_nil).and_return(:as_empty)
        serializer.serialize(parent, nil, rule)
        expect(parent.children).not_to be_empty
        expect(parent.children.first.value).to eq([])
      end
    end

    context "with empty collection" do
      it "creates element with empty array" do
        serializer.serialize(parent, [], rule)
        expect(parent.children).not_to be_empty
        expect(parent.children.first.value).to eq([])
      end
    end

    context "with array collection" do
      it "creates element with children for each item" do
        allow(value_serializer).to receive(:serialize_item).and_return("item1", "item2")
        serializer.serialize(parent, ["item1", "item2"], rule)
        expect(parent.children).not_to be_empty
      end
    end

    context "with keyed collection" do
      let(:rule) { build_rule(is_collection: true, collection_info: { child_mappings: { id: :key } }) }

      it "creates keyed hash element" do
        item_class = Class.new do
          attr_accessor :id, :name

          def initialize(id, name)
            @id = id
            @name = name
          end
        end

        items = [item_class.new("key1", "value1"), item_class.new("key2", "value2")]
        serializer.serialize(parent, items, rule)
        expect(parent.children).not_to be_empty
        expect(parent.children.first.value).to be_a(Hash)
      end
    end
  end

  describe "#serialize_array" do
    let(:parent) { Lutaml::KeyValue::DataModel::Element.new("root") }
    let(:rule) { build_rule(serialized_name: "items") }

    it "creates element with empty array for empty items" do
      serializer.serialize_array(parent, [], rule, {})
      expect(parent.children.first.value).to eq([])
    end

    it "creates element with children for each item" do
      allow(value_serializer).to receive(:serialize_item).and_return("item1", "item2")
      serializer.serialize_array(parent, ["item1", "item2"], rule, {})
      expect(parent.children).not_to be_empty
    end
  end

  describe "#serialize_keyed" do
    let(:parent) { Lutaml::KeyValue::DataModel::Element.new("root") }
    let(:rule) { build_rule(serialized_name: "items") }
    let(:key_attribute) { :id }
    let(:child_mappings) { { id: :key } }

    it "creates keyed hash element" do
      item_class = Class.new do
        attr_accessor :id, :name

        def initialize(id, name)
          @id = id
          @name = name
        end

        # Return false for include? check so we don't try to serialize attributes
        def self.include?(mod)
          false
        end
      end

      items = [item_class.new("key1", "value1")]
      serializer.serialize_keyed(parent, items, rule, key_attribute, child_mappings, {})
      expect(parent.children).not_to be_empty
      # The value should be a hash (may be empty if no attributes to serialize)
      expect(parent.children.first.value).to be_a(Hash)
    end
  end

  describe "RenderPolicy integration" do
    it "includes RenderPolicy module" do
      expect(serializer.class.ancestors).to include(Lutaml::Model::RenderPolicy)
    end

    it "includes render_nil? method" do
      expect(serializer).to respond_to(:render_nil?)
    end

    it "includes render_empty? method" do
      expect(serializer).to respond_to(:render_empty?)
    end
  end

  # Helper method to build a mock rule
  def build_rule(attribute_type: nil, attribute_name: :test, serialized_name: "test",
                 is_collection: false, collection_info: nil, child_transformation: nil)
    rule = double("CompiledRule",
                  attribute_type: attribute_type,
                  attribute_name: attribute_name,
                  serialized_name: serialized_name,
                  collection?: is_collection,
                  collection_info: collection_info,
                  child_transformation: child_transformation)
    # Stub all option calls with sensible defaults
    allow(rule).to receive(:option).and_return(nil)
    allow(rule).to receive(:option).with(:render_nil).and_return(false)
    allow(rule).to receive(:option).with(:root_mappings).and_return(nil)
    allow(rule).to receive(:option).with(:value_map).and_return(nil)
    allow(rule).to receive(:option).with(:render_default).and_return(false)
    rule
  end
end
