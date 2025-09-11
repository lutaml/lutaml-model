require "spec_helper"
require "lutaml/model/xml/ox_adapter"

module OxAdapter
  module ModelLevelNamespaceDefinition
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
        namespace "https://example.com/xsd-namespace", "xsd"

        map_attribute :status, to: :status
        map_element :name, to: :name
      end
    end
  end

  module MappingLevelElementMapping
    class ElementName < Lutaml::Model::Serializable
      attribute :name, :string

      xml do
        root "name"
        namespace "https://example.com/namespace", "ewn"

        map_content to: :name
      end
    end

    class ElementWithNamespace < Lutaml::Model::Serializable
      attribute :status, :string
      attribute :name, ElementName

      xml do
        root "ElementWithNamespace"
        namespace "https://example.com/namespace", "ewn"

        map_attribute :status, to: :status, namespace: "https://example.com/namespace-1", prefix: "ewn1"
        map_element :name, to: :name
      end
    end
  end
end

RSpec.describe "Lutaml::Model::XML::OxAdapter" do
  let(:previous_adapter) { Lutaml::Model::Config.xml_adapter }

  before do
    previous_adapter
    Lutaml::Model::Config.xml_adapter_type = :ox
  end

  after { Lutaml::Model::Config.xml_adapter = previous_adapter }

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
        OxAdapter::ModelLevelNamespaceDefinition::ElementWithoutNamespace.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(xml)
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
        OxAdapter::ModelLevelNamespaceDefinition::ElementWithoutNamespace.from_xml(xml)
      end

      it "reads attributes but doesn't read child elements" do
        expect(instances.name).to be_nil
        expect(instances.to_xml.strip).to eq(expected_xml)
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
        OxAdapter::ModelLevelNamespaceDefinition::ElementWithNamespace.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(xml)
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
        OxAdapter::ModelLevelNamespaceDefinition::ElementWithNamespace.from_xml(xml)
      end

      it "reads attributes but doesn't read child elements" do
        expect(instances.name).to be_nil
        expect(instances.to_xml.strip).to eq(expected_xml)
      end
    end
  end

  describe "with model-level defined prefix" do
    context "with prefix xml successfully processed" do
      let(:xml) do
        <<~XML
          <xsd:PrefixedWithPrefixedNamespace xmlns:xsd="https://example.com/xsd-namespace" status="active">
            <xsd:name>Test Element</xsd:name>
          </xsd:PrefixedWithPrefixedNamespace>
        XML
      end

      let(:instances) do
        OxAdapter::ModelLevelNamespaceDefinition::PrefixedWithPrefixedNamespace.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(xml)
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

      let(:expected_xml) { "<xsd:PrefixedWithPrefixedNamespace xmlns:xsd=\"https://example.com/xsd-namespace\" status=\"active\"/>\n" }

      let(:instances) do
        OxAdapter::ModelLevelNamespaceDefinition::PrefixedWithPrefixedNamespace.from_xml(xml)
      end

      it "reads attributes but doesn't read child elements" do
        expect(instances.name).to be_nil
        expect(instances.to_xml).to eq(expected_xml)
      end
    end
  end

  describe "with mapping-level defined namespace" do
    context "with namespace xml successfully processed" do
      let(:xml) do
        <<~XML
          <ewn:ElementWithNamespace xmlns:ewn="https://example.com/namespace" xmlns:ewn1="https://example.com/namespace-1" ewn1:status="active">
            <ewn:name>Test Element</ewn:name>
          </ewn:ElementWithNamespace>
        XML
      end

      let(:instances) do
        OxAdapter::MappingLevelElementMapping::ElementWithNamespace.from_xml(xml)
      end

      it "round trips successfully" do
        expect(instances.to_xml).to eq(xml)
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

      let(:expected_xml) { "<ewn:ElementWithNamespace xmlns:ewn=\"https://example.com/namespace\" xmlns:ewn1=\"https://example.com/namespace-1\"/>" }

      let(:instances) do
        OxAdapter::MappingLevelElementMapping::ElementWithNamespace.from_xml(xml)
      end

      it "reads attributes but doesn't read child elements" do
        expect(instances.name).to be_nil
        expect(instances.to_xml.strip).to eq(expected_xml)
      end
    end
  end
end
