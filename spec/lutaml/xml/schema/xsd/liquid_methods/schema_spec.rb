# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::Schema do
  let(:schema_xml) do
    <<~XML
      <schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              targetNamespace="http://example.com/test"
              xmlns="http://example.com/test">
        <xs:element name="GammaElement" type="xs:string"/>
        <xs:element name="AlphaElement" type="xs:string"/>
        <xs:element name="BetaElement" type="xs:string"/>

        <xs:complexType name="WidgetType">
          <xs:sequence>
            <xs:element ref="GammaElement"/>
          </xs:sequence>
        </xs:complexType>
        <xs:complexType name="AlphaType">
          <xs:sequence>
            <xs:element ref="AlphaElement"/>
          </xs:sequence>
        </xs:complexType>
        <xs:complexType name="BetaType">
          <xs:sequence>
            <xs:element ref="BetaElement"/>
          </xs:sequence>
        </xs:complexType>

        <xs:attributeGroup name="CoreAttributes">
          <xs:attribute name="id" type="xs:string"/>
        </xs:attributeGroup>
        <xs:attributeGroup name="BaseAttributes">
          <xs:attribute name="base" type="xs:string"/>
        </xs:attributeGroup>
        <xs:attributeGroup name="ZetaAttributes">
          <xs:attribute name="zeta" type="xs:string"/>
        </xs:attributeGroup>
      </schema>
    XML
  end

  let(:schema) { Lutaml::Xml::Schema::Xsd.parse(schema_xml, validate_schema: false) }

  it "sorts elements by name" do
    expect(schema.elements_sorted_by_name.map(&:name))
      .to eq(%w[AlphaElement BetaElement GammaElement])
  end

  it "sorts complex types by name" do
    expect(schema.complex_types_sorted_by_name.map(&:name))
      .to eq(%w[AlphaType BetaType WidgetType])
  end

  it "sorts attribute groups by name" do
    expect(schema.attribute_groups_sorted_by_name.map(&:name))
      .to eq(%w[BaseAttributes CoreAttributes ZetaAttributes])
  end

  it "exposes sorting helpers through Liquid" do
    expect(schema.to_liquid.elements_sorted_by_name.map(&:name))
      .to eq(%w[AlphaElement BetaElement GammaElement])
  end
end
