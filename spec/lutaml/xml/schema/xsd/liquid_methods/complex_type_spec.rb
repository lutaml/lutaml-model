# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::ComplexType do
  let(:schema_xml) do
    <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              targetNamespace="http://example.com/test"
              xmlns="http://example.com/test">
        <xs:element name="UsesRoot" type="RootType"/>
        <xs:element name="DirectChild" type="xs:string"/>

        <xs:attributeGroup name="TestAttributeGroup">
          <xs:attribute name="GroupAttr1" type="xs:string"/>
        </xs:attributeGroup>

        <xs:group name="TestGroup">
          <xs:sequence>
            <xs:element name="GroupElement1" type="xs:string"/>
          </xs:sequence>
        </xs:group>

        <xs:complexType name="RootType">
          <xs:sequence>
            <xs:element ref="DirectChild"/>
            <xs:choice>
              <xs:element name="ChoiceElement1" type="xs:string"/>
            </xs:choice>
            <xs:group ref="TestGroup"/>
          </xs:sequence>
          <xs:attribute name="RootAttr" type="xs:string"/>
          <xs:attributeGroup ref="TestAttributeGroup"/>
        </xs:complexType>
      </schema>
    XML
  end

  let(:schema) { Lutaml::Xml::Schema::Xsd.parse(schema_xml, validate_schema: false) }
  let(:root_type) { schema.complex_type.find { |complex_type| complex_type.name == "RootType" } }

  it "finds elements that use the complex type" do
    expect(root_type.used_by.any? { |element| element.type == "RootType" }).to be true
  end

  it "collects attributes from the type and attribute groups" do
    expect(root_type.attribute_elements.map(&:name)).to include("RootAttr", "GroupAttr1")
  end

  it "returns direct and nested child elements" do
    expect(root_type.direct_child_elements.map(&:class))
      .to include(Lutaml::Xml::Schema::Xsd::Sequence)
    expect(root_type.child_elements.map(&:referenced_name))
      .to include("DirectChild", "ChoiceElement1", "GroupElement1")
  end

  it "detects element usage inside nested structures" do
    expect(root_type.find_elements_used("DirectChild")).to be true
    expect(root_type.find_elements_used("NonExistent")).to be false
  end

  it "collects attributes from simple content extensions" do
    simple_content_schema = <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="SimpleType">
          <xs:simpleContent>
            <xs:extension base="xs:string">
              <xs:attribute name="ExtendedAttr" type="xs:string"/>
            </xs:extension>
          </xs:simpleContent>
        </xs:complexType>
      </schema>
    XML

    parsed = Lutaml::Xml::Schema::Xsd.parse(simple_content_schema, validate_schema: false)
    expect(parsed.complex_type.first.attribute_elements.map(&:name)).to include("ExtendedAttr")
  end
end
