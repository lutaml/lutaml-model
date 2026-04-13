# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "XSD attribute-based liquid helpers" do
  let(:schema_xml) do
    <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              targetNamespace="http://example.com/test"
              xmlns="http://example.com/test">
        <xs:attribute name="TestAttribute" type="xs:string"/>
        <xs:attributeGroup name="TestAttributeGroup">
          <xs:attribute name="GroupAttr1" type="xs:string"/>
          <xs:attribute name="GroupAttr2" type="xs:int"/>
        </xs:attributeGroup>

        <xs:complexType name="RootType">
          <xs:attribute name="RootAttr" type="xs:string"/>
          <xs:attributeGroup ref="TestAttributeGroup"/>
        </xs:complexType>
      </schema>
    XML
  end

  let(:schema) { Lutaml::Xml::Schema::Xsd.parse(schema_xml, validate_schema: false) }
  let(:test_attr) { schema.attribute.find { |attribute| attribute.name == "TestAttribute" } }
  let(:attr_group) { schema.attribute_group.find { |group| group.name == "TestAttributeGroup" } }
  let(:root_type) { schema.complex_type.find { |type| type.name == "RootType" } }

  it "reports attribute cardinality and reference resolution" do
    test_attr.use = "required"

    ref_attr = Lutaml::Xml::Schema::Xsd::Attribute.new(
      __register: Lutaml::Xml::Schema::Xsd.register,
    )
    ref_attr.ref = "TestAttribute"
    ref_attr.__root = schema

    expect(test_attr.cardinality).to eq("1")
    expect(ref_attr.referenced_name).to eq("TestAttribute")
    expect(ref_attr.referenced_type).to eq("xs:string")
    expect(test_attr.to_liquid.cardinality).to eq("1")
  end

  it "finds complex types using an attribute group" do
    expect(attr_group.used_by).to include(root_type)
    expect(attr_group.find_used_by(root_type)).to be true
  end

  it "expands attribute groups into their attributes" do
    expect(attr_group.attribute_elements.map(&:name))
      .to contain_exactly("GroupAttr1", "GroupAttr2")
  end

  it "resolves referenced attribute groups" do
    ref_group = Lutaml::Xml::Schema::Xsd::AttributeGroup.new(
      __register: Lutaml::Xml::Schema::Xsd.register,
    )
    ref_group.ref = "TestAttributeGroup"
    ref_group.__root = schema

    expect(ref_group.referenced_object).to eq(attr_group)
  end
end
