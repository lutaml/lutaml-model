# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema"
require "tmpdir"

# Runtime XSD-to-classes compilation (#251): Schema.from_xml compiles a
# schema into generated Serializable classes, and with load_classes: the
# classes are available in-process for direct parsing and serialization —
# no generated files on disk.
RSpec.describe "runtime XSD class loading" do
  let(:xsd) do
    <<~XSD
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="EntryType">
          <xs:sequence>
            <xs:element name="name" type="xs:string"/>
            <xs:element name="year" type="xs:integer"/>
          </xs:sequence>
          <xs:attribute name="id" type="xs:string" use="required"/>
        </xs:complexType>
        <xs:element name="entry" type="EntryType"/>
      </xs:schema>
    XSD
  end

  let(:instance_xml) do
    <<~XML
      <entry id="e1"><name>Alpha</name><year>2024</year></entry>
    XML
  end

  it "compiles a schema, loads the classes, and round-trips an instance" do
    Dir.mktmpdir do |dir|
      Lutaml::Model::Schema.from_xml(
        xsd, output_dir: File.join(dir, "runtime_pilot_models"),
             load_classes: true
      )

      doc = RuntimePilotModels::EntryType.from_xml(instance_xml)

      expect(doc.name).to eq("Alpha")
      expect(doc.year).to eq(2024)
      expect(doc.id).to eq("e1")

      expect(doc.to_xml).to include("<name>Alpha</name>")
      expect(doc.to_xml).to include("<year>2024</year>")
      expect(doc.to_xml).to include('id="e1"')
    end
  end
end
