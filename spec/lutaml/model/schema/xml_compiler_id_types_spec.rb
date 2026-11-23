# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema"
require "tmpdir"

RSpec.describe "XML compiler ID built-in types" do
  let(:register_id) { :xml_compiler_id_types }

  let(:schema) do
    <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:simpleType name="ItemIdentifier">
          <xs:restriction base="xs:ID">
            <xs:pattern value="[A-Za-z_][A-Za-z0-9_.-]*"/>
          </xs:restriction>
        </xs:simpleType>
        <xs:complexType name="RecordType">
          <xs:sequence>
            <xs:element name="identifier" type="xs:ID"/>
            <xs:element name="reference" type="xs:IDREF"/>
            <xs:element name="label" type="xs:string"/>
          </xs:sequence>
          <xs:attribute name="source" type="xs:IDREF"/>
          <xs:attribute name="key" type="ItemIdentifier"/>
        </xs:complexType>
        <xs:element name="record" type="RecordType"/>
      </xs:schema>
    XSD
  end

  before { stub_const("IdTypesModels", Module.new) }

  after { Lutaml::Model::GlobalRegister.remove(register_id) }

  it "compiles and hydrates ID restrictions, IDREF members, and string controls" do
    expect(Object.const_defined?(:ID, false)).to be(false)

    Dir.mktmpdir("xml_compiler_id_types") do |dir|
      Lutaml::Model::Schema.from_xml(
        schema, output_dir: File.join(dir, "id_types_models"),
                register_id: register_id, load_classes: true
      )

      record = IdTypesModels::RecordType.from_xml(<<~XML, register: register_id)
        <record source="source-a" key="record-a">
          <identifier>record-a</identifier><reference>record-a</reference>
          <label>plain text</label>
        </record>
      XML

      expect(record.identifier).to eq("record-a")
      expect(record.reference).to eq("record-a")
      expect(record.source).to eq("source-a")
      expect(record.key).to eq("record-a")
      expect(record.label).to eq("plain text")
      expect(Object.const_defined?(:ID, false)).to be(false)
    end
  end
end
