# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require_relative "../../support/xml_mapping_namespaces"

# Test for issue #504: Default namespace handling
# https://github.com/lutaml/lutaml-model/issues/504
module DefaultNamespaceSpec
  class NestedItem < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :value, :string

    xml do
      element "nested"
      namespace ExampleNamespaceDefault
      map_element "name", to: :name
      map_element "value", to: :value
    end
  end

  class SimpleRoot < Lutaml::Model::Serializable
    attribute :child, :string

    xml do
      element "root"
      namespace ExampleNamespaceDefault
      map_element "child", to: :child
    end
  end

  class NestedRoot < Lutaml::Model::Serializable
    attribute :title, :string
    attribute :nested, NestedItem

    xml do
      element "root"
      namespace ExampleNamespaceDefault
      map_element "title", to: :title
      map_element "nested", to: :nested
    end
  end

  class CollectionItem < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "item"
      namespace ExampleNamespaceDefault
      map_element "name", to: :name
    end
  end

  class CollectionRoot < Lutaml::Model::Serializable
    attribute :items, CollectionItem, collection: true

    xml do
      element "root"
      namespace ExampleNamespaceDefault
      map_element "item", to: :items
    end
  end
end

RSpec.describe DefaultNamespaceSpec do
  shared_examples "default namespace serialization" do |adapter_name|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_name
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    context "with simple element in default namespace" do
      let(:xml_with_default_ns) do
        <<~XML
          <root xmlns="http://example.com/ns">
            <child>Content</child>
          </root>
        XML
      end

      it "deserializes elements correctly" do
        parsed = DefaultNamespaceSpec::SimpleRoot.from_xml(xml_with_default_ns)
        expect(parsed.child).to eq("Content")
      end

      it "serializes with default namespace" do
        instance = DefaultNamespaceSpec::SimpleRoot.new(child: "Content")
        xml = instance.to_xml

        # W3C Compliance: Parent uses default namespace (xmlns="..."),
        # child element has NO namespace directive on map_element,
        # and namespace has element_form_default: :unqualified (W3C default),
        # so child is in BLANK namespace and MUST declare xmlns="".
        #
        # All adapters (Nokogiri, Ox, Oga) now correctly add xmlns=""
        # to explicitly place child in blank namespace.
        expect(xml).to include('xmlns="http://example.com/ns"')
        expect(xml).to include('<child xmlns="">Content</child>')
      end

      it "round-trips XML correctly" do
        parsed = DefaultNamespaceSpec::SimpleRoot.from_xml(xml_with_default_ns)
        xml = parsed.to_xml
        reparsed = DefaultNamespaceSpec::SimpleRoot.from_xml(xml)

        expect(reparsed.child).to eq(parsed.child)
      end
    end

    context "with nested elements in default namespace" do
      let(:xml_with_nested) do
        <<~XML
          <root xmlns="http://example.com/ns">
            <title>Test</title>
            <nested>
              <name>Item</name>
              <value>Data</value>
            </nested>
          </root>
        XML
      end

      it "deserializes nested elements correctly" do
        parsed = DefaultNamespaceSpec::NestedRoot.from_xml(xml_with_nested)
        expect(parsed.title).to eq("Test")
        expect(parsed.nested.name).to eq("Item")
        expect(parsed.nested.value).to eq("Data")
      end

      it "round-trips nested elements correctly" do
        parsed = DefaultNamespaceSpec::NestedRoot.from_xml(xml_with_nested)
        xml = parsed.to_xml
        reparsed = DefaultNamespaceSpec::NestedRoot.from_xml(xml)

        expect(reparsed.title).to eq(parsed.title)
        expect(reparsed.nested.name).to eq(parsed.nested.name)
        expect(reparsed.nested.value).to eq(parsed.nested.value)
      end
    end

    context "with collection in default namespace" do
      let(:xml_with_collection) do
        <<~XML
          <root xmlns="http://example.com/ns">
            <item><name>First</name></item>
            <item><name>Second</name></item>
            <item><name>Third</name></item>
          </root>
        XML
      end

      it "deserializes collection correctly" do
        parsed = DefaultNamespaceSpec::CollectionRoot.from_xml(xml_with_collection)
        expect(parsed.items.length).to eq(3)
        expect(parsed.items.map(&:name)).to eq(["First", "Second", "Third"])
      end

      it "round-trips collection correctly" do
        parsed = DefaultNamespaceSpec::CollectionRoot.from_xml(xml_with_collection)
        xml = parsed.to_xml
        reparsed = DefaultNamespaceSpec::CollectionRoot.from_xml(xml)

        expect(reparsed.items.length).to eq(parsed.items.length)
        expect(reparsed.items.map(&:name)).to eq(parsed.items.map(&:name))
      end
    end
  end

  describe Lutaml::Model::Xml::NokogiriAdapter do
    it_behaves_like "default namespace serialization", described_class
  end

  describe Lutaml::Model::Xml::OxAdapter do
    it_behaves_like "default namespace serialization", described_class if TestAdapterConfig.adapter_enabled?(:ox)
  end

  describe Lutaml::Model::Xml::OgaAdapter do
    it_behaves_like "default namespace serialization", described_class if TestAdapterConfig.adapter_enabled?(:oga)
  end
end
