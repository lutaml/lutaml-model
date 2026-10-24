# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "xs:list nested simpleType mapping" do
  it "maps the inline simpleType of a list from the parsed XSD" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="r">
          <xs:simpleType>
            <xs:list>
              <xs:simpleType>
                <xs:restriction base="xs:string">
                  <xs:enumeration value="a"/>
                </xs:restriction>
              </xs:simpleType>
            </xs:list>
          </xs:simpleType>
        </xs:element>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    list = schema.element.first.simple_type.list

    expect(list.simple_type).to be_a(Lutaml::Xml::Schema::Xsd::SimpleType)
    values = Array(list.simple_type.restriction.enumeration).map(&:value)
    expect(values).to eq(["a"])
  end
end
