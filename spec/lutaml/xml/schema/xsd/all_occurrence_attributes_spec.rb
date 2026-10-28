# frozen_string_literal: true

require_relative "../../../../spec_helper"
require "lutaml/xml/schema/xsd"

# #1046: xs:all carried its occurrence bounds mapped by their Ruby names
# (min_occurs/max_occurs), so minOccurs="0" was silently dropped at parse
# and never re-emitted. Sequence, choice and group already map the XML
# names; all now does too.
RSpec.describe "Xsd::All occurrence attributes" do
  let(:xsd) do
    <<~XSD
      <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <xsd:element name="elt1">
          <xsd:complexType>
            <xsd:all minOccurs="0" maxOccurs="1">
              <xsd:element name="elt2"/>
            </xsd:all>
          </xsd:complexType>
        </xsd:element>
      </xsd:schema>
    XSD
  end

  it "reads the occurrence bounds" do
    doc = Lutaml::Xml::Schema::Xsd.parse(xsd)
    all = doc.element.first.complex_type.all

    expect(all.min_occurs).to eq("0")
    expect(all.max_occurs).to eq("1")
  end

  it "round-trips them as the XML attribute names" do
    xml = Lutaml::Xml::Schema::Xsd.parse(xsd).to_xml

    expect(xml).to include('minOccurs="0"')
    expect(xml).to include('maxOccurs="1"')
    expect(xml).not_to include("min_occurs")
    expect(xml).not_to include("max_occurs")
  end

  it "keeps an xs:all without bounds boundless" do
    doc = Lutaml::Xml::Schema::Xsd.parse(
      <<~XSD,
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <xsd:element name="elt1">
            <xsd:complexType>
              <xsd:all><xsd:element name="elt2"/></xsd:all>
            </xsd:complexType>
          </xsd:element>
        </xsd:schema>
      XSD
    )

    all = doc.element.first.complex_type.all

    expect(all.min_occurs).to be_nil
    expect(all.max_occurs).to be_nil
  end
end
