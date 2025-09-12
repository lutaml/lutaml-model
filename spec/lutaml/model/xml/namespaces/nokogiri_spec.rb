require "spec_helper"
require "lutaml/model/xml/nokogiri_adapter"

module NokogiriAdapter
  module ModelLevel
    class ElementWithoutNamespace < Lutaml::Model::Serializable
      attribute :status, :string
      attribute :name, :string

      xml do
        root "ElementWithoutNamespace"

        map_attribute :status, to: :status
        map_element :name, to: :name
      end
    end

    class ElementWithNamespace < Lutaml::Model::Serializable
      attribute :status, :string
      attribute :name, :string

      xml do
        root "ElementWithNamespace"
        namespace "https://example.com/namespace"

        map_attribute :status, to: :status
        map_element :name, to: :name
      end
    end

    class PrefixedWithPrefixedNamespace < Lutaml::Model::Serializable
      attribute :status, :string
      attribute :name, :string

      xml do
        root "PrefixedWithPrefixedNamespace"
        namespace "https://example.com/namespace", "xsd"

        map_attribute :status, to: :status
        map_element :name, to: :name
      end
    end

    class OptionalPrefixed < Lutaml::Model::Serializable
      attribute :status, :string
      attribute :name, :string
      attribute :description, :string
      attribute :age, :string

      xml do
        root "OptionalPrefixed"
        namespace "https://example.com/optional-prefixed"
        prefix "opf", optional: true

        map_attribute :status, to: :status
        map_element :name, to: :name
        map_element :description, to: :description
        map_element :age, to: :age
      end
    end
  end

  module MappingLevelElementMapping
    class ElementName < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :status, :string

      xml do
        root "name", ordered: true
        namespace "https://example.com/namespace", "ewn"

        map_content to: :name
        map_attribute :status, to: :status
      end
    end

    class ElementWithNamespace < Lutaml::Model::Serializable
      attribute :status, :string
      attribute :name, ElementName, collection: true

      xml do
        root "ElementWithNamespace", ordered: true
        namespace "https://example.com/namespace", "ewn"

        map_attribute :status, to: :status, namespace: "https://example.com/namespace-1", prefix: "ewn1"
        map_element :name, to: :name
      end
    end
  end
end

RSpec.describe "Lutaml::Model::XML::NokogiriAdapter" do
  before { Lutaml::Model::Config.xml_adapter_type = :nokogiri }

  describe "without model-level defined namespace" do
    context "without namespace xml processes successfully" do
      let(:xml) do
        <<~XML
          <ElementWithoutNamespace status="active">
            <name>Test Element</name>
          </ElementWithoutNamespace>
        XML
      end

      let(:instances) do
        NokogiriAdapter::ModelLevel::ElementWithoutNamespace.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(xml.strip)
      end
    end

    context "when xml doesn't completely process with namespace" do
      let(:xml) do
        <<~XML
          <ElementWithoutNamespace xmlns="https://example.com/namespace" status="active">
            <name>Test Element</name>
          </ElementWithoutNamespace>
        XML
      end

      let(:expected_xml) { "<ElementWithoutNamespace status=\"active\"/>" }

      let(:instances) do
        NokogiriAdapter::ModelLevel::ElementWithoutNamespace.from_xml(xml)
      end

      it "reads attributes but doesn't read child elements" do
        expect(instances.name).to be_nil
        expect(instances.to_xml).to eq(expected_xml)
      end
    end
  end

  describe "with model-level defined namespace" do
    context "with namespace xml successfully processed" do
      let(:xml) do
        <<~XML
          <ElementWithNamespace xmlns="https://example.com/namespace" status="active">
            <name>Test Element</name>
          </ElementWithNamespace>
        XML
      end

      let(:instances) do
        NokogiriAdapter::ModelLevel::ElementWithNamespace.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(xml.strip)
      end
    end

    context "without namespace xml doesn't process properly" do
      let(:xml) do
        <<~XML
          <ElementWithNamespace status="active">
            <name>Test Element</name>
          </ElementWithNamespace>
        XML
      end

      let(:expected_xml) { "<ElementWithNamespace xmlns=\"https://example.com/namespace\" status=\"active\"/>" }

      let(:instances) do
        NokogiriAdapter::ModelLevel::ElementWithNamespace.from_xml(xml)
      end

      it "reads attributes but doesn't read child elements" do
        expect(instances.name).to be_nil
        expect(instances.to_xml).to eq(expected_xml)
      end
    end
  end

  describe "with model-level defined prefix" do
    context "with prefix xml successfully processed" do
      let(:xml) do
        <<~XML
          <xsd:PrefixedWithPrefixedNamespace xmlns:xsd="https://example.com/namespace" status="active">
            <xsd:name>Test Element</xsd:name>
          </xsd:PrefixedWithPrefixedNamespace>
        XML
      end

      let(:instances) do
        NokogiriAdapter::ModelLevel::PrefixedWithPrefixedNamespace.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(xml.strip)
      end
    end

    context "without namespace xml doesn't process properly" do
      let(:xml) do
        <<~XML
          <PrefixedWithPrefixedNamespace status="active">
            <name>Test Element</name>
          </PrefixedWithPrefixedNamespace>
        XML
      end

      let(:expected_xml) { "<xsd:PrefixedWithPrefixedNamespace xmlns:xsd=\"https://example.com/namespace\" status=\"active\"/>" }

      let(:instances) do
        NokogiriAdapter::ModelLevel::PrefixedWithPrefixedNamespace.from_xml(xml)
      end

      it "reads attributes but doesn't read child elements" do
        expect(instances.name).to be_nil
        expect(instances.to_xml).to eq(expected_xml)
      end
    end
  end

  describe "with model-level defined prefix with `optional: true` argument" do
    context "with prefix xml successfully processed" do
      let(:xml) do
        <<~XML
          <OptionalPrefixed status="active" xmlns:opf="https://example.com/optional-prefixed">
            <name>John Doe</name>
            <opf:description>Sample description</opf:description>
            <age>30</age>
          </OptionalPrefixed>
        XML
      end

      let(:expected_xml) do
        <<~XML.strip
          <opf:OptionalPrefixed xmlns:opf="https://example.com/optional-prefixed" status="active">
            <opf:name>John Doe</opf:name>
            <opf:description>Sample description</opf:description>
            <opf:age>30</opf:age>
          </opf:OptionalPrefixed>
        XML
      end

      let(:instances) do
        NokogiriAdapter::ModelLevel::OptionalPrefixed.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(expected_xml)
      end
    end
  end

  describe "with mapping-level defined namespace" do
    context "with namespace xml successfully processed" do
      let(:xml) do
        <<~XML.strip
          <ewn:ElementWithNamespace xmlns:ewn="https://example.com/namespace" xmlns:ewn1="https://example.com/namespace-1" ewn1:status="active"><ewn:name status="active">Test Element</ewn:name></ewn:ElementWithNamespace>
        XML
      end

      let(:instances) do
        NokogiriAdapter::MappingLevelElementMapping::ElementWithNamespace.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(xml)
      end
    end

    context "without namespace xml doesn't process properly" do
      let(:xml) do
        <<~XML
          <ElementWithNamespace ewn1:status="inactive">
            <name>Test Element</name>
          </ElementWithNamespace>
        XML
      end

      let(:expected_xml) do
        <<~XML.strip
          <ewn:ElementWithNamespace xmlns:ewn="https://example.com/namespace" xmlns:ewn1="https://example.com/namespace-1"></ewn:ElementWithNamespace>
        XML
      end

      let(:instances) do
        NokogiriAdapter::MappingLevelElementMapping::ElementWithNamespace.from_xml(xml)
      end

      it "reads attributes but doesn't read child elements" do
        expect(instances.name).to be_nil
        expect(instances.to_xml.strip).to eq(expected_xml)
      end
    end
  end
end
