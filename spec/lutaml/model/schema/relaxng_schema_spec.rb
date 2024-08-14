require "spec_helper"
require_relative "../../../fixtures/vase"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::RelaxngSchema do
  it "generates RelaxNG schema for Vase class" do
    schema_relaxng = described_class.generate(Vase)
    expected_relaxng = <<~XML
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

    expect(schema_relaxng).to be_equivalent_to(expected_relaxng)
  end
end
