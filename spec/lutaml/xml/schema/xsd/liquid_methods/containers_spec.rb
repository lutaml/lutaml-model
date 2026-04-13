# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "XSD container liquid helpers" do
  let(:schema_xml) do
    <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              targetNamespace="http://example.com/test"
              xmlns="http://example.com/test">
        <xs:element name="DirectChild" type="xs:string"/>
        <xs:element name="ChoiceElement1" type="xs:string"/>
        <xs:element name="NestedSeqElement" type="xs:string"/>
        <xs:element name="GroupElement1" type="xs:string"/>

        <xs:group name="TestGroup">
          <xs:sequence>
            <xs:element ref="GroupElement1"/>
            <xs:element name="GroupElement2" type="xs:int"/>
          </xs:sequence>
        </xs:group>

        <xs:complexType name="RootType">
          <xs:sequence>
            <xs:element ref="DirectChild"/>
            <xs:choice>
              <xs:element ref="ChoiceElement1"/>
              <xs:element name="ChoiceElement2" type="xs:int"/>
            </xs:choice>
            <xs:sequence>
              <xs:element ref="NestedSeqElement"/>
            </xs:sequence>
            <xs:group ref="TestGroup"/>
          </xs:sequence>
        </xs:complexType>
      </schema>
    XML
  end

  let(:schema) { Lutaml::Xml::Schema::Xsd.parse(schema_xml, validate_schema: false) }
  let(:root_type) { schema.complex_type.find { |complex_type| complex_type.name == "RootType" } }
  let(:sequence) { root_type.sequence }
  let(:choice) { root_type.sequence.choice.first }
  let(:group) { schema.group.find { |item| item.name == "TestGroup" } }

  it "collects child elements from sequences" do
    expect(sequence.child_elements.map(&:referenced_name))
      .to include("DirectChild", "ChoiceElement1", "ChoiceElement2", "NestedSeqElement", "GroupElement1", "GroupElement2")
  end

  it "collects child elements from choices" do
    expect(choice.child_elements.map(&:referenced_name))
      .to include("ChoiceElement1", "ChoiceElement2")
  end

  it "collects child elements from groups" do
    expect(group.child_elements.map(&:referenced_name))
      .to contain_exactly("GroupElement1", "GroupElement2")
  end

  it "detects referenced elements within nested containers" do
    expect(sequence.find_elements_used("DirectChild")).to be true
    expect(choice.find_elements_used("ChoiceElement1")).to be true
    expect(group.find_elements_used("GroupElement1")).to be true
  end

  it "resolves referenced groups" do
    ref_group = Lutaml::Xml::Schema::Xsd::Group.new(
      __register: Lutaml::Xml::Schema::Xsd.register,
    )
    ref_group.ref = "TestGroup"
    ref_group.__root = schema

    expect(ref_group.referenced_object).to eq(group)
  end
end
