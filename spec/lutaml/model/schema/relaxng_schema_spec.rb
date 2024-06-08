# spec/schema/relaxng_schema_spec.rb
require "spec_helper"
require_relative "../../fixtures/vase"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::RelaxngSchema do
  it "generates RelaxNG schema for Vase class" do
    schema_relaxng = described_class.generate(Vase)
    expected_relaxng = <<-XML
<element name="Vase">
  <complexType>
    <sequence>
      <element name="height" type="float"/>
      <element name="diameter" type="float"/>
      <element name="material" type="string"/>
      <element name="manufacturer" type="string"/>
    </sequence>
  </complexType>
</element>
    XML

    expect(Nokogiri::XML(schema_relaxng).to_xml).to eq(Nokogiri::XML(expected_relaxng).to_xml)
  end
end
