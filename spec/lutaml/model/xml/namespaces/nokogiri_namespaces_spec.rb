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
end
