require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require_relative "../../support/xml_mapping_namespaces"

module ExceptSpecs
  class Annotation < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :appinfo, :string
    attribute :documentation, :string

    xml do
      root "annotation", mixed: true
      namespace XsdNamespace

      map_element :documentation, to: :documentation
      map_element :appinfo, to: :appinfo
      map_attribute :id, to: :id
    end
  end

  class Attribute < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ref, :string
    attribute :name, :string
    attribute :annotation, Annotation

    xml do
      root "attribute", mixed: true
      namespace XsdNamespace

      map_attribute :id, to: :id
      map_attribute :ref, to: :ref
      map_attribute :name, to: :name
      map_element :annotation, to: :annotation
    end
  end

  class AttributeGroup < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ref, :string
    attribute :name, :string
    attribute :annotation, Annotation
    attribute :attribute, Attribute

    xml do
      root "attributeGroup", mixed: true
      namespace XsdNamespace

      map_attribute :id, to: :id
      map_attribute :ref, to: :ref
      map_attribute :name, to: :name
      map_element :attribute, to: :attribute
      map_element :annotation, to: :annotation
    end
  end

  class Schema < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :attribute, Attribute
    attribute :attribute_group, AttributeGroup

    xml do
      root "schema", mixed: true
      namespace XsdNamespace

      map_attribute :id, to: :id
      map_element :attribute, to: :attribute
      map_element :attributeGroup, to: :attribute_group
    end
  end
end

RSpec.describe "Except" do
  shared_examples "xml" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    context "when :except option is used for XML conversion" do
      let(:xml) do
        <<~XML
          <xsd:schema id="testing" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <xsd:attribute id="attr1" name="test">
              <xsd:annotation>
                <xsd:documentation>A test model</xsd:documentation>
              </xsd:annotation>
            </xsd:attribute>
            <xsd:attributeGroup id="attr2">
              <xsd:annotation>
                <xsd:documentation>Another test model</xsd:documentation>
              </xsd:annotation>
              <xsd:attribute id="nested_attr" name="nested">
                <xsd:annotation>
                  <xsd:documentation>Nested attribute</xsd:documentation>
                </xsd:annotation>
              </xsd:attribute>
            </xsd:attributeGroup>
          </xsd:schema>
        XML
      end

      let(:xml_without_annotations) do
        # W3C-compliant: Use DEFAULT namespace format
        <<~XML
          <schema xmlns="http://www.w3.org/2001/XMLSchema" id="testing">
            <attribute id="attr1" name="test"/>
            <attributeGroup id="attr2">
              <attribute id="nested_attr" name="nested"/>
            </attributeGroup>
          </schema>
        XML
      end

      let(:xml_without_annotations_and_ids) do
        # W3C-compliant: Use DEFAULT namespace format
        <<~XML
          <schema xmlns="http://www.w3.org/2001/XMLSchema">
            <attribute name="test"/>
            <attributeGroup>
              <attribute name="nested"/>
            </attributeGroup>
          </schema>
        XML
      end

      let(:parsed_instances) { ExceptSpecs::Schema.from_xml(xml) }

      it "excludes specified elements from the XML output" do
        parsed_xml = parsed_instances.to_xml(except: %i[annotation])
        expect(parsed_xml).to be_xml_equivalent_to(xml_without_annotations)
      end

      it "excludes specified attributes and elements from the XML output" do
        parsed_xml = parsed_instances.to_xml(except: %i[annotation id])
        expect(parsed_xml).to be_xml_equivalent_to(xml_without_annotations_and_ids)
      end
    end
  end

  describe "yaml" do
    context "when :except option is used for YAML (key-value) conversion" do
      let(:yaml) do
        <<~YAML
          ---
          id: testing
          attribute:
            id: attr1
            name: test
            annotation:
              documentation: A test model
          attribute_group:
            id: attr2
            annotation:
              documentation: Another test model
            attribute:
              id: nested_attr
              name: nested
              annotation:
                documentation: Nested attribute
        YAML
      end

      let(:yaml_without_annotations) do
        <<~YAML
          ---
          id: testing
          attribute:
            id: attr1
            name: test
          attribute_group:
            id: attr2
            attribute:
              id: nested_attr
              name: nested
        YAML
      end

      let(:yaml_without_annotations_and_ids) do
        <<~YAML
          ---
          attribute:
            name: test
          attribute_group:
            attribute:
              name: nested
        YAML
      end

      let(:parsed_instances) { ExceptSpecs::Schema.from_yaml(yaml) }

      it "excludes 'annotation' keys from the YAML output" do
        parsed_yaml = parsed_instances.to_yaml(except: %i[annotation])
        # Compare YAML strings, not XML
        expect(parsed_yaml).to eq(yaml_without_annotations)
      end

      it "excludes 'annotation' and 'id' from the YAML output" do
        parsed_yaml = parsed_instances.to_yaml(except: %i[annotation id])
        # Compare YAML strings, not XML
        expect(parsed_yaml).to eq(yaml_without_annotations_and_ids)
      end
    end
  end

  describe Lutaml::Model::Xml::NokogiriAdapter do
    it_behaves_like "xml", described_class
  end

  describe Lutaml::Model::Xml::OgaAdapter do
    it_behaves_like "xml", described_class
  end

  describe Lutaml::Model::Xml::OxAdapter do
    it_behaves_like "xml", described_class
  end
end
