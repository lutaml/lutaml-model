# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::Keyref do
  it "maps the refer attribute from the parsed XSD" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="catalog">
          <xs:keyref name="refKey" refer="itemKey"/>
        </xs:element>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    keyref = Array(schema.element.first.keyref).first

    expect(keyref).not_to be_nil
    expect(keyref.refer).to eq("itemKey")
  end
end
