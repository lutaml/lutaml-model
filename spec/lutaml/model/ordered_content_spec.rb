# spec/lutaml/model/ordered_content_spec.rb

require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require_relative "../../fixtures/sample_model"
require_relative "../../support/xml_mapping_namespaces"

module OrderedContentSpec
  class RootOrderedContent < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :bold, :string, collection: true
    attribute :italic, :string, collection: true
    attribute :underline, :string
    attribute :content, :string

    xml do
      root "RootOrderedContent", ordered: true

      map_attribute :id, to: :id
      map_element :bold, to: :bold
      map_element :italic, to: :italic
      map_element :underline, to: :underline
      map_content to: :content
    end
  end

  module PrefixedElements
    class Annotation < Lutaml::Model::Serializable
      attribute :content, :string

      xml do
        element "annotation"
        namespace ExampleSchemaNamespace

        map_content to: :content
      end
    end

    class Element < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :status, :string
      attribute :annotation, Annotation

      xml do
        root "element", ordered: true

        namespace ExampleSchemaNamespace

        map_attribute :name, to: :name
        map_attribute :status, to: :status
        map_element :annotation, to: :annotation
      end
    end

    class Schema < Lutaml::Model::Serializable
      attribute :element, Element, collection: true

      xml do
        root "schema", ordered: true
        namespace ExampleSchemaNamespace

        map_element :element, to: :element
      end
    end
  end
end

RSpec.describe "OrderedContent" do
  shared_examples "ordered content behavior" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    context "when ordered: true is set at root" do
      let(:xml) do
        <<~XML
          <RootOrderedContent id="123">
            The Earth's Moon rings like a <bold>bell</bold> when struck by
            meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
            its surface is covered in <underline>craters</underline>.
            Ain't that <bold>cool</bold>?
          </RootOrderedContent>
        XML
      end

      it "deserializes and serializes ordered content correctly" do
        obj = OrderedContentSpec::RootOrderedContent.from_xml(xml)

        # Verify correct parsing
        expect(obj.id).to eq("123")
        expect(obj.bold).to eq(["bell", "cool"])
        expect(obj.italic).to eq(["384,400 km"])
        expect(obj.underline).to eq("craters")
        expect(obj.content.to_s).to match(/The Earth's Moon rings like a/)
        expect(obj.content.to_s).to match(/Ain't that/)

        # Verify round-trip preserves data
        # (Note: exact XML format differs between adapters in ordered mode)
        round_trip = OrderedContentSpec::RootOrderedContent.from_xml(obj.to_xml)
        expect(round_trip.id).to eq(obj.id)
        expect(round_trip.bold).to eq(obj.bold)
        expect(round_trip.italic).to eq(obj.italic)
        expect(round_trip.underline).to eq(obj.underline)
        expect(round_trip.content.to_s).to match(/The Earth's Moon rings like a/)
      end
    end

    context "when ordered: true is set for prefixed elements" do
      let(:xml) do
        <<~XML
          <xsd:schema xmlns:xsd="http://example.com/schema">
            <xsd:element>
              <xsd:annotation>Testing annotation</xsd:annotation>
            </xsd:element>
          </xsd:schema>
        XML
      end

      let(:serialized) do
        OrderedContentSpec::PrefixedElements::Schema.from_xml(xml).to_xml
      end

      it "deserializes and serializes ordered prefixed elements correctly for prefixed elements" do
        # W3C Compliance: Models with namespace use default format by default
        # Input uses prefix format, but output uses default format (semantically equivalent)
        expected_xml = <<~XML
          <schema xmlns="http://example.com/schema">
            <element>
              <annotation>Testing annotation</annotation>
            </element>
          </schema>
        XML

        expect(serialized).to be_xml_equivalent_to(expected_xml)
      end
    end
  end

  describe Lutaml::Model::Xml::NokogiriAdapter do
    it_behaves_like "ordered content behavior", described_class
  end

  describe Lutaml::Model::Xml::OxAdapter do
    it_behaves_like "ordered content behavior", described_class
  end

  describe Lutaml::Model::Xml::OgaAdapter do
    it_behaves_like "ordered content behavior", described_class
  end
end
