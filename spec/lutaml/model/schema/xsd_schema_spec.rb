# spec/schema/xsd_schema_spec.rb
require "spec_helper"
require_relative "../../fixtures/vase"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::XsdSchema do
  it "generates XSD schema for Vase class" do
    schema_xsd = described_class.generate(Vase)
    expected_xsd = <<-XML
<schema xmlns="http://www.w3.org/2001/XMLSchema">
  <element name="Vase">
    <complexType>
      <sequence>
        <element name="height" type="xs:float"/>
        <element name="diameter" type="xs:float"/>
        <element name="material" type="xs:string"/>
        <element name="manufacturer" type="xs:string"/>
      </sequence>
    </complexType>
  </element>
</schema>
    XML

    expect(Nokogiri::XML(schema_xsd).to_xml).to eq(Nokogiri::XML(expected_xsd).to_xml)
  end
end
