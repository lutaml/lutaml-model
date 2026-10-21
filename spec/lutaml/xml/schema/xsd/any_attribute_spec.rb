# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "xs:anyAttribute mappings" do
  it "maps anyAttribute on a complexType from the parsed XSD" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:attribute name="a"/>
          <xs:anyAttribute namespace="##other" processContents="strict"/>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    wildcard = schema.complex_type.first.any_attribute

    expect(wildcard).not_to be_nil
    expect(wildcard.namespace).to eq("##other")
    expect(wildcard.process_contents).to eq("strict")
  end

  it "maps anyAttribute inside a simpleContent extension" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:simpleContent>
            <xs:extension base="xs:string">
              <xs:anyAttribute namespace="##local"/>
            </xs:extension>
          </xs:simpleContent>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    extension = schema.complex_type.first.simple_content.extension
    wildcard = extension.any_attribute

    expect(wildcard).not_to be_nil
    expect(wildcard.namespace).to eq("##local")
  end

  it "maps anyAttribute inside a complexContent extension" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:complexContent>
            <xs:extension base="xs:anyType">
              <xs:anyAttribute namespace="##targetNamespace"/>
            </xs:extension>
          </xs:complexContent>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    extension = schema.complex_type.first.complex_content.extension
    wildcard = extension.any_attribute

    expect(wildcard).not_to be_nil
    expect(wildcard.namespace).to eq("##targetNamespace")
  end
end
