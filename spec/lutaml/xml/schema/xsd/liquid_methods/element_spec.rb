# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::Element do
  let(:schema_xml) do
    <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              targetNamespace="http://example.com/test"
              xmlns="http://example.com/test">
        <xs:element name="RootElement" type="RootType"/>
        <xs:element name="ReferencedElement" type="xs:string"/>
        <xs:element name="SimpleElement" type="xs:string"/>

        <xs:complexType name="RootType">
          <xs:sequence>
            <xs:element name="DirectChild" type="xs:string"/>
          </xs:sequence>
          <xs:attribute name="RootAttr" type="xs:string"/>
        </xs:complexType>

        <xs:complexType name="UsesRootType">
          <xs:sequence>
            <xs:element name="UsesRoot" type="RootType"/>
          </xs:sequence>
        </xs:complexType>

        <xs:complexType name="UsesRootElement">
          <xs:sequence>
            <xs:element ref="RootElement"/>
          </xs:sequence>
        </xs:complexType>
      </schema>
    XML
  end

  let(:schema) { Lutaml::Xml::Schema::Xsd.parse(schema_xml, validate_schema: false) }
  let(:root_element) { schema.element.find { |element| element.name == "RootElement" } }
  let(:referenced_element) { schema.element.find { |element| element.name == "ReferencedElement" } }
  let(:simple_element) { schema.element.find { |element| element.name == "SimpleElement" } }

  it "assigns the parsed schema as the root context" do
    expect(root_element.lutaml_root).to eq(schema)
  end

  it "returns attributes from the referenced complex type" do
    expect(root_element.attributes.map(&:name)).to include("RootAttr")
  end

  it "returns child elements from the referenced complex type" do
    expect(root_element.child_elements.map(&:name)).to include("DirectChild")
  end

  it "returns child data from inline anonymous complex types" do
    inline_schema_xml = <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              targetNamespace="http://example.com/test">
        <xs:element name="InlineRoot">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="InlineChild" type="xs:string"/>
            </xs:sequence>
            <xs:attribute name="InlineAttr" type="xs:string"/>
          </xs:complexType>
        </xs:element>
      </schema>
    XML

    parsed = Lutaml::Xml::Schema::Xsd.parse(inline_schema_xml, validate_schema: false)
    inline_root = parsed.element.find { |element| element.name == "InlineRoot" }

    expect(inline_root.attributes.map(&:name)).to include("InlineAttr")
    expect(inline_root.child_elements.map(&:name)).to include("InlineChild")
  end

  it "returns nil child data when no complex type is referenced" do
    expect(simple_element.attributes).to be_nil
    expect(simple_element.child_elements).to be_nil
  end

  it "resolves referenced objects and types" do
    ref_element = described_class.new(__register: Lutaml::Xml::Schema::Xsd.register)
    ref_element.ref = "ReferencedElement"
    ref_element.lutaml_root = schema

    expect(ref_element.referenced_name).to eq("ReferencedElement")
    expect(ref_element.referenced_type).to eq("xs:string")
    expect(ref_element.referenced_object).to eq(referenced_element)
  end

  it "resolves referenced complex types" do
    expect(root_element.referenced_complex_type.name).to eq("RootType")
    expect(simple_element.referenced_complex_type).to be_nil
  end

  it "finds complex types that use the element" do
    expect(root_element.used_by.map(&:name)).to include("UsesRootElement")
  end

  it "finds complex types that use a qualified element reference" do
    qualified_schema_xml = <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              xmlns:test="http://example.com/test"
              targetNamespace="http://example.com/test">
        <xs:element name="QualifiedRoot" type="xs:string"/>
        <xs:complexType name="UsesQualifiedRoot">
          <xs:sequence>
            <xs:element ref="test:QualifiedRoot"/>
          </xs:sequence>
        </xs:complexType>
      </schema>
    XML

    parsed = Lutaml::Xml::Schema::Xsd.parse(qualified_schema_xml, validate_schema: false)
    qualified_root = parsed.element.find { |element| element.name == "QualifiedRoot" }

    expect(qualified_root.used_by.map(&:name)).to include("UsesQualifiedRoot")
  end

  it "exposes helper methods through Liquid" do
    expect(root_element.to_liquid.referenced_name).to eq("RootElement")
  end
end
