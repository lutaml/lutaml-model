require "spec_helper"

# Module to namespace all test classes and prevent global pollution
module NamespacePrinciplesSpec
  # Namespace definitions
  class FirstItemNamespace < Lutaml::Model::XmlNamespace
    prefix_default "first"
    uri "http://example.com/first"
  end

  class SecondItemNamespace < Lutaml::Model::XmlNamespace
    prefix_default "second"
    uri "http://example.com/second"
  end

  class WrapperNamespace < Lutaml::Model::XmlNamespace
    prefix_default "wr"
    uri "http://example.com/wrapper"
  end

  # Test model classes
  class NativeItem < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "first_item"
      namespace FirstItemNamespace
      map_element "name", to: :name
    end
  end

  class NativeItemNames < Lutaml::Model::Serializable
    attribute :name, :string, collection: true

    xml do
      element "item_names"
      namespace FirstItemNamespace
      map_element "name", to: :name
    end
  end

  class FirstNamespacedName < Lutaml::Model::Type::String
    xml_namespace FirstItemNamespace
  end

  class SecondNamespacedName < Lutaml::Model::Type::String
    xml_namespace SecondItemNamespace
  end

  class NamespacedItem < Lutaml::Model::Serializable
    attribute :name, FirstNamespacedName
    attribute :alt_name, SecondNamespacedName

    xml do
      element "second_item"
      namespace SecondItemNamespace
      map_element "name", to: :name
      map_element "alt_name", to: :alt_name
    end
  end

  class NamespacedItem2 < Lutaml::Model::Serializable
    attribute :name, FirstNamespacedName
    attribute :alt_name, SecondNamespacedName

    xml do
      element "second_item"
      namespace SecondItemNamespace
      map_element "name", to: :name
      map_element "alt_name", to: :alt_name
    end
  end

  class Wrapper < Lutaml::Model::Serializable
    attribute :items, NamespacedItem2, collection: true

    xml do
      element "wrapper"
      namespace WrapperNamespace
      map_element "item", to: :items
    end
  end

  class SimpleItem < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :value, :integer

    xml do
      element "item"
      namespace FirstItemNamespace
      map_element "name", to: :name
      map_element "value", to: :value
    end
  end

  class NativeItem2 < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "first_item"
      namespace FirstItemNamespace
      map_element "name", to: :name
    end
  end

  class NativeItemCollection < Lutaml::Model::Serializable
    attribute :items, NativeItem2, collection: true

    xml do
      element "items"
      namespace FirstItemNamespace
      map_element "item", to: :items
    end
  end

  class NativeItem3 < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "first_item"
      namespace FirstItemNamespace
      map_element "name", to: :name
    end
  end

  class InheritedNativeItem < NativeItem3
    attribute :description, :string

    xml do
      map_element "description", to: :description
    end
  end

  class InheritedCollection < Lutaml::Model::Serializable
    attribute :items, InheritedNativeItem, collection: true

    xml do
      element "items"
      namespace FirstItemNamespace
      map_element "item", to: :items
    end
  end

  class CollectionItem < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "item"
      namespace FirstItemNamespace
      map_element "value", to: :value
    end
  end

  class ItemsCollection < Lutaml::Model::Collection
    instances :items, CollectionItem

    xml do
      element "items"
      namespace FirstItemNamespace
      map_element "item", to: :items
    end
  end

  class SecondItem < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "item"
      namespace SecondItemNamespace
      map_element "value", to: :value
    end
  end

  class MixedNamespaceCollection < Lutaml::Model::Collection
    instances :items, SecondItem

    xml do
      element "collection"
      namespace FirstItemNamespace
      map_element "item", to: :items
    end
  end

  class ThirdItem < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "item"
      namespace FirstItemNamespace
      map_element "name", to: :name
    end
  end

  class SameNamespaceCollection < Lutaml::Model::Collection
    instances :items, ThirdItem

    xml do
      element "collection"
      namespace FirstItemNamespace
      map_element "item", to: :items
    end
  end

  class BaseCollItem < Lutaml::Model::Serializable
    attribute :type, :string

    xml do
      element "base_item"
      map_attribute "type", to: :type
    end
  end

  class FirstTypeItem < BaseCollItem
    attribute :first_value, :string

    xml do
      element "item"
      namespace WrapperNamespace
      map_element "first_value", to: :first_value
    end
  end

  class SecondTypeItem < BaseCollItem
    attribute :second_value, :string

    xml do
      element "item"
      namespace WrapperNamespace
      map_element "second_value", to: :second_value
    end
  end

  class PolyCollection < Lutaml::Model::Collection
    instances :items, BaseCollItem, polymorphic: [FirstTypeItem, SecondTypeItem]

    xml do
      element "poly_collection"
      namespace WrapperNamespace
      map_element "item", to: :items, polymorphic: {
        attribute: "type",
        class_map: {
          "first" => "NamespacePrinciplesSpec::FirstTypeItem",
          "second" => "NamespacePrinciplesSpec::SecondTypeItem"
        }
      }
    end
  end

  class FirstTypeItemInDifferentNamespace < BaseCollItem
    attribute :first_value, :string

    xml do
      element "item"
      namespace FirstItemNamespace
      map_element "first_value", to: :first_value
    end
  end

  class SecondTypeItemInDifferentNamespace < BaseCollItem
    attribute :second_value, :string

    xml do
      element "item"
      namespace SecondItemNamespace
      map_element "second_value", to: :second_value
    end
  end

  class PolyCollectionMixed < Lutaml::Model::Collection
    instances :items, BaseCollItem, polymorphic: [
      FirstTypeItemInDifferentNamespace,
      SecondTypeItemInDifferentNamespace
    ]

    xml do
      element "poly_collection"
      namespace WrapperNamespace
      map_element "item", to: :items, polymorphic: {
        attribute: "type",
        class_map: {
          "first" => "NamespacePrinciplesSpec::FirstTypeItemInDifferentNamespace",
          "second" => "NamespacePrinciplesSpec::SecondTypeItemInDifferentNamespace"
        }
      }
    end
  end

  class NoNamespaceItem < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "item"
      map_element "name", to: :name
    end
  end

  class NativeItem4 < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "first_item"
      namespace FirstItemNamespace
      map_element "name", to: :name
    end
  end
end

RSpec.describe "XML Namespace principles" do

  describe "Principle 1: All attributes belong to their own namespaces" do
    context "native types with namespace" do
      let(:instance) { NamespacePrinciplesSpec::NativeItem.new(name: "Item Name") }

      it "applies namespace to native type elements with default namespace" do
        xml = instance.to_xml

        # W3C-compliant: Child element without namespace needs xmlns=""
        # when parent uses default namespace format
        expected_xml = <<~XML
          <first_item xmlns="http://example.com/first">
            <name xmlns="">Item Name</name>
          </first_item>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "applies namespace to native type elements with prefixed namespace" do
        xml = instance.to_xml(prefix: true)

        expected_xml = <<~XML
          <first:first_item xmlns:first="http://example.com/first">
            <name>Item Name</name>
          </first:first_item>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "round-trips correctly with either presentation" do
        xml_default = instance.to_xml
        xml_prefixed = instance.to_xml(prefix: true)

        parsed_default = NamespacePrinciplesSpec::NativeItem.from_xml(xml_default)
        parsed_prefixed = NamespacePrinciplesSpec::NativeItem.from_xml(xml_prefixed)

        expect(parsed_default.name).to eq("Item Name")
        expect(parsed_prefixed.name).to eq("Item Name")
        expect(parsed_default.name).to eq(parsed_prefixed.name)
      end
    end

    context "native types in collections" do
      let(:instance) { NamespacePrinciplesSpec::NativeItemNames.new(name: ["Item Name 1", "Item Name 2"]) }

      it "applies namespace to each collection item with default namespace" do
        xml = instance.to_xml

        # W3C-compliant: Child elements without namespace need xmlns=""
        # when parent uses default namespace format
        expected_xml = <<~XML
          <item_names xmlns="http://example.com/first">
            <name xmlns="">Item Name 1</name>
            <name xmlns="">Item Name 2</name>
          </item_names>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "applies namespace to each collection item with prefixed namespace" do
        xml = instance.to_xml(prefix: true)

        expected_xml = <<~XML
          <first:item_names xmlns:first="http://example.com/first">
            <name>Item Name 1</name>
            <name>Item Name 2</name>
          </first:item_names>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "Type::Value with namespace" do
      let(:instance) { NamespacePrinciplesSpec::NamespacedItem.new(name: "Item Name", alt_name: "Alt Item Name") }

      it "applies Type namespace correctly with default namespace" do
        xml = instance.to_xml

        # Type namespace feature: Type's namespace is hoisted and used with prefix
        # - FirstNamespacedName has FirstItemNamespace -> <first:name>
        # - SecondNamespacedName has SecondItemNamespace (same as parent) -> <alt_name>
        expected_xml = <<~XML
          <second_item xmlns="http://example.com/second" xmlns:first="http://example.com/first">
            <first:name>Item Name</first:name>
            <alt_name>Alt Item Name</alt_name>
          </second_item>
        XML
        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "applies Type namespace correctly with prefixed namespace" do
        xml = instance.to_xml(prefix: true)

        # Type namespace feature with parent using prefix
        # - Both FirstNamespacedName and SecondNamespacedName use their respective prefixes
        expected_xml = <<~XML
          <second:second_item xmlns:second="http://example.com/second" xmlns:first="http://example.com/first">
            <first:name>Item Name</first:name>
            <second:alt_name>Alt Item Name</second:alt_name>
          </second:second_item>
        XML
        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "round-trips correctly with either presentation" do
        xml_default = instance.to_xml
        xml_prefixed = instance.to_xml(prefix: true)

        parsed_default = NamespacePrinciplesSpec::NamespacedItem.from_xml(xml_default)
        parsed_prefixed = NamespacePrinciplesSpec::NamespacedItem.from_xml(xml_prefixed)

        expect(parsed_default.name).to eq("Item Name")
        expect(parsed_default.alt_name).to eq("Alt Item Name")
        expect(parsed_prefixed.name).to eq("Item Name")
        expect(parsed_prefixed.alt_name).to eq("Alt Item Name")
      end
    end

    context "collections of namespaced items" do
      let(:item) { NamespacePrinciplesSpec::NamespacedItem2.new(name: "Item Name", alt_name: "Alt Item Name") }
      let(:instance) { NamespacePrinciplesSpec::Wrapper.new(items: [item]) }

      it "applies namespaces correctly in nested structure with default namespace" do
        xml = instance.to_xml

        # Type namespace feature in nested structure
        # - Wrapper uses its namespace (WrapperNamespace)
        # - Item uses its namespace (SecondItemNamespace)
        # - Type namespaces are hoisted with prefix
        expected_xml = <<~XML
          <wrapper xmlns="http://example.com/wrapper">
            <item xmlns="http://example.com/second" xmlns:first="http://example.com/first">
              <first:name>Item Name</first:name>
              <alt_name>Alt Item Name</alt_name>
            </item>
          </wrapper>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "applies namespaces correctly in nested structure with prefixed namespace" do
        xml = instance.to_xml(prefix: true)

        # NOTE: Current implementation reuses parent prefix for child namespace
        # This may need fixing - child should use its own namespace declaration
        # Type namespace feature with all prefixed
        expected_xml = <<~XML
          <wr:wrapper xmlns:wr="http://example.com/wrapper">
            <wr:item xmlns:wr="http://example.com/second" xmlns:first="http://example.com/first">
              <first:name>Item Name</first:name>
              <wr:alt_name>Alt Item Name</wr:alt_name>
            </wr:item>
          </wr:wrapper>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end
    end
  end

  describe "Principle 2: Prefix vs default is ONLY presentation" do
    let(:instance) { NamespacePrinciplesSpec::SimpleItem.new(name: "Test", value: 42) }

    it "produces semantically identical XML with different presentations" do
      xml_default = instance.to_xml
      xml_prefixed = instance.to_xml(prefix: true)

      parsed_default = NamespacePrinciplesSpec::SimpleItem.from_xml(xml_default)
      parsed_prefixed = NamespacePrinciplesSpec::SimpleItem.from_xml(xml_prefixed)

      expect(parsed_default.name).to eq(parsed_prefixed.name)
      expect(parsed_default.value).to eq(parsed_prefixed.value)
    end

    it "can parse default namespace format" do
      xml = <<~XML
        <item xmlns="http://example.com/first">
          <name>Test</name>
          <value>42</value>
        </item>
      XML

      parsed = NamespacePrinciplesSpec::SimpleItem.from_xml(xml)
      expect(parsed.name).to eq("Test")
      expect(parsed.value).to eq(42)
    end

    it "can parse prefixed namespace format" do
      xml = <<~XML
        <first:item xmlns:first="http://example.com/first">
          <first:name>Test</first:name>
          <first:value>42</first:value>
        </first:item>
      XML

      parsed = NamespacePrinciplesSpec::SimpleItem.from_xml(xml)
      expect(parsed.name).to eq("Test")
      expect(parsed.value).to eq(42)
    end

    it "can parse custom prefixed namespace format" do
      xml = <<~XML
        <another_first:item xmlns:another_first="http://example.com/first">
          <another_first:name>Test</another_first:name>
          <another_first:value>42</another_first:value>
        </another_first:item>
      XML

      parsed = NamespacePrinciplesSpec::SimpleItem.from_xml(xml)
      expect(parsed.name).to eq("Test")
      expect(parsed.value).to eq(42)
    end

    it "can cross-parse: parse prefixed, serialize default" do
      xml_input = <<~XML
        <first:item xmlns:first="http://example.com/first">
          <first:name>Test</first:name>
          <first:value>42</first:value>
        </first:item>
      XML

      parsed = NamespacePrinciplesSpec::SimpleItem.from_xml(xml_input)
      xml_output = parsed.to_xml

      # W3C-compliant: Child elements without namespace need xmlns=""
      expected_xml = <<~XML
        <item xmlns="http://example.com/first">
          <name xmlns="">Test</name>
          <value xmlns="">42</value>
        </item>
      XML

      expect(xml_output).to be_xml_equivalent_to(expected_xml)
    end

    it "can cross-parse: parse default, serialize prefixed" do
      xml_input = <<~XML
        <item xmlns="http://example.com/first">
          <name>Test</name>
          <value>42</value>
        </item>
      XML

      parsed = NamespacePrinciplesSpec::SimpleItem.from_xml(xml_input)
      xml_output = parsed.to_xml(prefix: true)

      expected_xml = <<~XML
        <first:item xmlns:first="http://example.com/first">
          <name>Test</name>
          <value>42</value>
        </first:item>
      XML

      expect(xml_output).to be_xml_equivalent_to(expected_xml)
    end
  end

  describe "Principle 3: Collections follow same rules" do
    context "model collections" do
      let(:instance) do
        NamespacePrinciplesSpec::NativeItemCollection.new(items: [
          NamespacePrinciplesSpec::NativeItem2.new(name: "Item 1"),
          NamespacePrinciplesSpec::NativeItem2.new(name: "Item 2")
        ])
      end

      it "applies same namespace rules to each item" do
        xml = instance.to_xml

        # W3C-compliant: Child elements without namespace need xmlns=""
        expected_xml = <<~XML
          <items xmlns="http://example.com/first">
            <item>
              <name xmlns="">Item 1</name>
            </item>
            <item>
              <name xmlns="">Item 2</name>
            </item>
          </items>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "inherited items in collections" do
      let(:instance) do
        NamespacePrinciplesSpec::InheritedCollection.new(items: [
          NamespacePrinciplesSpec::InheritedNativeItem.new(name: "Item Name", description: "Item Description")
        ])
      end

      # InheritedNativeItem inherits NativeItem3, which is in FirstItemNamespace
      it "uses inherited namespace for inherited attributes" do
        xml = instance.to_xml

        # W3C-compliant: When collection and item model share same namespace,
        # native type children implicitly inherit that namespace
        expected_xml = <<~XML
          <items xmlns="http://example.com/first">
            <item>
              <name>Item Name</name>
              <description>Item Description</description>
            </item>
          </items>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "applies namespace correctly with prefix" do
        xml = instance.to_xml(prefix: true)

        # With prefix format, children inherit the prefixed namespace
        expected_xml = <<~XML
          <first:items xmlns:first="http://example.com/first">
            <first:item>
              <first:name>Item Name</first:name>
              <first:description>Item Description</first:description>
            </first:item>
          </first:items>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end
    end
  end

  describe "Lutaml::Model::Collection with namespaces" do
    context "Collection class with own namespace" do
      let(:collection) do
        NamespacePrinciplesSpec::ItemsCollection.new([
          NamespacePrinciplesSpec::CollectionItem.new(value: "Value 1"),
          NamespacePrinciplesSpec::CollectionItem.new(value: "Value 2")
        ])
      end

      it "applies namespace to collection root and items with default namespace" do
        xml = collection.to_xml

        # W3C-compliant: Child elements without namespace need xmlns=""
        expected_xml = <<~XML
          <items xmlns="http://example.com/first">
            <item>
              <value xmlns="">Value 1</value>
            </item>
            <item>
              <value xmlns="">Value 2</value>
            </item>
          </items>
        XML
        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "applies namespace to collection root and items with prefixed namespace" do
        xml = collection.to_xml(prefix: true)

        expected_xml = <<~XML
          <first:items xmlns:first="http://example.com/first">
            <first:item>
              <value>Value 1</value>
            </first:item>
            <first:item>
              <value>Value 2</value>
            </first:item>
          </first:items>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "round-trips correctly preserving data" do
        xml_default = collection.to_xml
        xml_prefixed = collection.to_xml(prefix: true)

        parsed_default = NamespacePrinciplesSpec::ItemsCollection.from_xml(xml_default)
        parsed_prefixed = NamespacePrinciplesSpec::ItemsCollection.from_xml(xml_prefixed)

        expect(parsed_default.items.size).to eq(2)
        expect(parsed_prefixed.items.size).to eq(2)
        expect(parsed_default.items[0].value).to eq("Value 1")
        expect(parsed_prefixed.items[0].value).to eq("Value 1")
      end
    end

    context "Collection with items in different namespace" do
      let(:collection) do
        NamespacePrinciplesSpec::MixedNamespaceCollection.new([
          NamespacePrinciplesSpec::SecondItem.new(value: "Value 1"),
          NamespacePrinciplesSpec::SecondItem.new(value: "Value 2")
        ])
      end

      it "handles collection and items in different namespaces" do
        xml = collection.to_xml

        # W3C-compliant: Child elements without namespace need xmlns=""
        expected_xml = <<~XML
          <collection xmlns="http://example.com/first">
            <item xmlns="http://example.com/second">
              <value xmlns="">Value 1</value>
            </item>
            <item xmlns="http://example.com/second">
              <value xmlns="">Value 2</value>
            </item>
          </collection>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "round-trips correctly with mixed namespaces" do
        xml = collection.to_xml
        parsed = NamespacePrinciplesSpec::MixedNamespaceCollection.from_xml(xml)

        expect(parsed.items.size).to eq(2)
        expect(parsed.items[0].value).to eq("Value 1")
        expect(parsed.items[1].value).to eq("Value 2")
      end
    end

    context "Collection with items in same namespace" do
      let(:collection) do
        NamespacePrinciplesSpec::SameNamespaceCollection.new([
          NamespacePrinciplesSpec::ThirdItem.new(name: "Name 1"),
          NamespacePrinciplesSpec::ThirdItem.new(name: "Name 2")
        ])
      end

      it "uses default namespace when collection and items share namespace" do
        xml = collection.to_xml

        # W3C-compliant: Child elements without namespace need xmlns=""
        expected_xml = <<~XML
          <collection xmlns="http://example.com/first">
            <item>
              <name xmlns="">Name 1</name>
            </item>
            <item>
              <name xmlns="">Name 2</name>
            </item>
          </collection>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "uses prefixed format when requested" do
        xml = collection.to_xml(prefix: true)

        expected_xml = <<~XML
          <first:collection xmlns:first="http://example.com/first">
            <first:item>
              <name>Name 1</name>
            </first:item>
            <first:item>
              <name>Name 2</name>
            </first:item>
          </first:collection>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "Polymorphic Collection with items in collection namespace" do
      let(:collection) do
        NamespacePrinciplesSpec::PolyCollection.new([
          NamespacePrinciplesSpec::FirstTypeItem.new(type: "first", first_value: "First Value"),
          NamespacePrinciplesSpec::SecondTypeItem.new(type: "second", second_value: "Second Value")
        ])
      end

      it "handles polymorphic items sharing collection namespace" do
        xml = collection.to_xml

        # W3C-compliant: Child elements without namespace need xmlns=""
        expected_xml = <<~XML
          <poly_collection xmlns="http://example.com/wrapper">
            <item type="first">
              <first_value xmlns="">First Value</first_value>
            </item>
            <item type="second">
              <second_value xmlns="">Second Value</second_value>
            </item>
          </poly_collection>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "round-trips polymorphic collection correctly" do
        xml = collection.to_xml
        parsed = NamespacePrinciplesSpec::PolyCollection.from_xml(xml)

        expect(parsed.items.size).to eq(2)
        expect(parsed.items[0]).to be_a(NamespacePrinciplesSpec::FirstTypeItem)
        expect(parsed.items[1]).to be_a(NamespacePrinciplesSpec::SecondTypeItem)
        # Both items are in WrapperNamespace, so second_value should be present
        expect(parsed.items[1].second_value).to eq("Second Value")
      end

      it "round-trips polymorphic collection correctly" do
        xml = collection.to_xml
        parsed = NamespacePrinciplesSpec::PolyCollection.from_xml(xml)

        expect(parsed.items.size).to eq(2)
        expect(parsed.items[0]).to be_a(NamespacePrinciplesSpec::FirstTypeItem)
        expect(parsed.items[1]).to be_a(NamespacePrinciplesSpec::SecondTypeItem)
        expect(parsed.items[0].first_value).to eq("First Value")
        expect(parsed.items[1].second_value).to eq("Second Value")
      end
    end

    context "Polymorphic Collection with items in different namespaces" do
      let(:collection) do
        NamespacePrinciplesSpec::PolyCollectionMixed.new([
          NamespacePrinciplesSpec::FirstTypeItemInDifferentNamespace.new(type: "first", first_value: "First Value"),
          NamespacePrinciplesSpec::SecondTypeItemInDifferentNamespace.new(type: "second", second_value: "Second Value")
        ])
      end

      it "handles polymorphic items in different namespaces" do
        xml = collection.to_xml

        # W3C-compliant: Child elements without namespace need xmlns=""
        expected_xml = <<~XML
          <poly_collection xmlns="http://example.com/wrapper">
            <item xmlns="http://example.com/first" type="first">
              <first_value xmlns="">First Value</first_value>
            </item>
            <item xmlns="http://example.com/second" type="second">
              <second_value xmlns="">Second Value</second_value>
            </item>
          </poly_collection>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "round-trips polymorphic collection correctly" do
        xml = collection.to_xml
        parsed = NamespacePrinciplesSpec::PolyCollectionMixed.from_xml(xml)

        expect(parsed.items.size).to eq(2)
        expect(parsed.items[0]).to be_a(NamespacePrinciplesSpec::FirstTypeItemInDifferentNamespace)
        expect(parsed.items[1]).to be_a(NamespacePrinciplesSpec::SecondTypeItemInDifferentNamespace)
        # Items in different namespaces should still round-trip correctly
        expect(parsed.items[1].second_value).to eq("Second Value")
      end

      it "round-trips polymorphic collection correctly" do
        xml = collection.to_xml
        parsed = NamespacePrinciplesSpec::PolyCollectionMixed.from_xml(xml)

        expect(parsed.items.size).to eq(2)
        expect(parsed.items[0]).to be_a(NamespacePrinciplesSpec::FirstTypeItemInDifferentNamespace)
        expect(parsed.items[1]).to be_a(NamespacePrinciplesSpec::SecondTypeItemInDifferentNamespace)
        expect(parsed.items[0].first_value).to eq("First Value")
        expect(parsed.items[1].second_value).to eq("Second Value")
      end
    end
  end

  describe "Edge cases and validation" do
    it "handles models without namespace correctly" do
      instance = NamespacePrinciplesSpec::NoNamespaceItem.new(name: "Test")
      xml = instance.to_xml

      expect(xml).not_to include("xmlns=")
      expect(xml).to include("<item")
      expect(xml).to include("<name>Test</name>")
    end

    it "handles custom prefix override" do
      instance = NamespacePrinciplesSpec::NativeItem4.new(name: "Test")
      xml = instance.to_xml(prefix: "custom")

      expect(xml).to include('xmlns:custom="http://example.com/first"')
      expect(xml).to include("<custom:first_item")
      expect(xml).to include("<name>Test</name>")
    end
  end
end
