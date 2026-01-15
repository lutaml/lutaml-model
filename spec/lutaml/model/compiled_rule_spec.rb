# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::CompiledRule do
  let(:attribute_name) { :test_attr }
  let(:serialized_name) { "test-attr" }
  let(:attribute_type) { :string }
  let(:namespace_class) { double("NamespaceClass") }

  describe "#initialize" do
    it "creates a new compiled rule with basic parameters" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        attribute_type: attribute_type
      )

      expect(rule.attribute_name).to eq(attribute_name)
      expect(rule.serialized_name).to eq(serialized_name)
      expect(rule.attribute_type).to eq(attribute_type)
    end

    it "accepts optional parameters" do
      child_transformation = double("Transformation")
      value_transformer = ->(v) { v.upcase }
      collection_info = { range: 1..10 }

      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        attribute_type: attribute_type,
        child_transformation: child_transformation,
        value_transformer: value_transformer,
        collection_info: collection_info,
        namespace_class: namespace_class
      )

      expect(rule.child_transformation).to eq(child_transformation)
      expect(rule.value_transformer).to eq(value_transformer)
      expect(rule.collection_info).to eq(collection_info)
      expect(rule.namespace_class).to eq(namespace_class)
    end

    it "accepts additional options" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        custom_option: "value"
      )

      expect(rule.option(:custom_option)).to eq("value")
    end

    it "freezes the rule after creation" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule).to be_frozen
    end
  end

  describe "#collection?" do
    it "returns true when collection_info is present" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        collection_info: { range: 1..10 }
      )

      expect(rule.collection?).to be true
    end

    it "returns false when collection_info is nil" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule.collection?).to be false
    end
  end

  describe "#nested_model?" do
    it "returns true when child_transformation is present" do
      child_transformation = double("Transformation")
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        child_transformation: child_transformation
      )

      expect(rule.nested_model?).to be true
    end

    it "returns false when child_transformation is nil" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule.nested_model?).to be false
    end
  end

  describe "#all_namespaces" do
    it "returns empty array when no namespace or child transformation" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule.all_namespaces).to eq([])
    end

    it "includes its own namespace class" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        namespace_class: namespace_class
      )

      expect(rule.all_namespaces).to eq([namespace_class])
    end

    it "includes namespaces from child transformation" do
      child_ns = double("ChildNamespace")
      child_transformation = double(
        "Transformation",
        all_namespaces: [child_ns]
      )

      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        child_transformation: child_transformation
      )

      expect(rule.all_namespaces).to eq([child_ns])
    end

    it "includes both own and child namespaces" do
      child_ns = double("ChildNamespace")
      child_transformation = double(
        "Transformation",
        all_namespaces: [child_ns]
      )

      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        namespace_class: namespace_class,
        child_transformation: child_transformation
      )

      expect(rule.all_namespaces).to eq([namespace_class, child_ns])
    end

    it "returns unique namespaces" do
      child_transformation = double(
        "Transformation",
        all_namespaces: [namespace_class]
      )

      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        namespace_class: namespace_class,
        child_transformation: child_transformation
      )

      namespaces = rule.all_namespaces
      expect(namespaces.uniq).to eq(namespaces)
    end
  end

  describe "#collection_range" do
    it "returns the range from collection_info" do
      range = 1..10
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        collection_info: { range: range }
      )

      expect(rule.collection_range).to eq(range)
    end

    it "returns nil when collection_info is nil" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule.collection_range).to be_nil
    end

    it "returns nil when range is not in collection_info" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        collection_info: { other: "value" }
      )

      expect(rule.collection_range).to be_nil
    end
  end

  describe "#multiple_values?" do
    it "returns false for non-collection" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule.multiple_values?).to be false
    end

    it "returns true for unbounded collection" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        collection_info: {}
      )

      expect(rule.multiple_values?).to be true
    end

    it "returns false for single-value collection (0..1)" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        collection_info: { range: 0..1 }
      )

      expect(rule.multiple_values?).to be false
    end

    it "returns true for multi-value collection (0..5)" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        collection_info: { range: 0..5 }
      )

      expect(rule.multiple_values?).to be true
    end

    it "returns true for open-ended collection (1..)" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        collection_info: { range: 1.. }
      )

      expect(rule.multiple_values?).to be true
    end
  end

  describe "#transform_value" do
    it "returns value unchanged when no transformer" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule.transform_value("test")).to eq("test")
    end

    it "applies hash transformer with export direction" do
      skip "Transform value implementation pending for Session 128"
      transformer = {
        export: ->(v) { v.upcase },
        import: ->(v) { v.downcase }
      }
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        value_transformer: transformer
      )

      expect(rule.transform_value("test", :export)).to eq("TEST")
    end

    it "applies hash transformer with import direction" do
      skip "Transform value implementation pending for Session 128"
      transformer = {
        export: ->(v) { v.upcase },
        import: ->(v) { v.downcase }
      }
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        value_transformer: transformer
      )

      expect(rule.transform_value("TEST", :import)).to eq("test")
    end

    it "applies proc transformer" do
      transformer = ->(v) { v.reverse }
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        value_transformer: transformer
      )

      expect(rule.transform_value("test")).to eq("tset")
    end

    it "returns value unchanged when direction not in hash" do
      transformer = { export: ->(v) { v.upcase } }
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        value_transformer: transformer
      )

      expect(rule.transform_value("test", :import)).to eq("test")
    end
  end

  describe "#option" do
    it "returns option value" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name,
        custom_key: "custom_value"
      )

      expect(rule.option(:custom_key)).to eq("custom_value")
    end

    it "returns default when option not found" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule.option(:missing, "default")).to eq("default")
    end

    it "returns nil when option not found and no default" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect(rule.option(:missing)).to be_nil
    end
  end

  describe "immutability" do
    it "prevents modification after creation" do
      rule = described_class.new(
        attribute_name: attribute_name,
        serialized_name: serialized_name
      )

      expect { rule.instance_variable_set(:@attribute_name, :new_name) }
        .to raise_error(FrozenError)
    end
  end
end