# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "XSD simple content liquid helpers" do
  let(:schema_xml) do
    <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              targetNamespace="http://example.com/test"
              xmlns="http://example.com/test">
        <xs:attributeGroup name="TestAttributeGroup">
          <xs:attribute name="GroupAttr1" type="xs:string"/>
        </xs:attributeGroup>

        <xs:complexType name="SimpleContentType">
          <xs:simpleContent>
            <xs:extension base="xs:string">
              <xs:attribute name="ExtendedAttr" type="xs:string"/>
              <xs:attributeGroup ref="TestAttributeGroup"/>
            </xs:extension>
          </xs:simpleContent>
        </xs:complexType>

        <xs:complexType name="SimpleContentWithBase">
          <xs:simpleContent base="xs:int"/>
        </xs:complexType>

        <xs:complexType name="SimpleContentWithRestriction">
          <xs:simpleContent>
            <xs:restriction base="xs:string">
              <xs:maxLength value="100"/>
            </xs:restriction>
          </xs:simpleContent>
        </xs:complexType>
      </schema>
    XML
  end

  let(:schema) { Lutaml::Xml::Schema::Xsd.parse(schema_xml, validate_schema: false) }
  let(:complex_types) { schema.complex_type }
  let(:simple_content) do
    complex_types.find { |complex_type| complex_type.name == "SimpleContentType" }.simple_content
  end

  it "returns attributes from the extension and attribute groups" do
    expect(simple_content.attribute_elements.map(&:name)).to include("ExtendedAttr", "GroupAttr1")
    expect(simple_content.to_liquid.attribute_elements.map(&:name)).to include("ExtendedAttr", "GroupAttr1")
  end

  it "resolves base type from extension, restriction, or inline base" do
    with_base = complex_types.find { |complex_type| complex_type.name == "SimpleContentWithBase" }
    with_restriction = complex_types.find { |complex_type| complex_type.name == "SimpleContentWithRestriction" }

    expect(simple_content.base_type).to eq("xs:string")
    expect(with_base.simple_content.base_type).to eq("xs:int")
    expect(with_restriction.simple_content.base_type).to eq("xs:string")
  end
end
