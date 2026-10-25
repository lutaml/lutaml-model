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

  # Anonymous (inline) complexTypes get CT_-prefixed internal names;
  # the generated classes must still (a) map skippable XSD built-ins
  # like xs:int to Lutaml primitives and (b) serialize the owning
  # element name, not the internal alias (#1014).
  describe "inline anonymous complexTypes" do
    let(:catalogue_xsd) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   elementFormDefault="qualified">
          <xs:element name="catalogue">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="title" type="xs:string"/>
                <xs:element name="entry" maxOccurs="unbounded">
                  <xs:complexType>
                    <xs:sequence>
                      <xs:element name="name" type="xs:string"/>
                      <xs:element name="year" type="xs:int"/>
                    </xs:sequence>
                    <xs:attribute name="id" type="xs:string" use="required"/>
                  </xs:complexType>
                </xs:element>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
      XSD
    end

    let(:catalogue_xml) do
      <<~XML
        <catalogue>
          <title>Test</title>
          <entry id="e1"><name>Alpha</name><year>2024</year></entry>
          <entry id="e2"><name>Beta</name><year>2025</year></entry>
        </catalogue>
      XML
    end

    it "maps xs:int to :integer and parses the instance" do
      Dir.mktmpdir do |dir|
        Lutaml::Model::Schema.from_xml(
          catalogue_xsd, output_dir: File.join(dir, "anon_ct_models"),
                         load_classes: true
        )

        entry_class = AnonCtModels::CTEntry
        expect(entry_class.attributes[:year].type).to eq(
          Lutaml::Model::Type::Integer,
        )

        doc = AnonCtModels::CTCatalogue.from_xml(catalogue_xml)

        expect(doc.title).to eq("Test")
        expect(doc.entry.map(&:name)).to eq(["Alpha", "Beta"])
        expect(doc.entry.map(&:year)).to eq([2024, 2025])
        expect(doc.entry.map(&:id)).to eq(%w[e1 e2])
      end
    end

    it "serializes the owning element name, not the CT_ alias" do
      Dir.mktmpdir do |dir|
        Lutaml::Model::Schema.from_xml(
          catalogue_xsd, output_dir: File.join(dir, "anon_ct_models2"),
                         load_classes: true
        )

        entry = AnonCtModels2::CTEntry.from_xml(
          '<entry id="z9"><name>Gamma</name><year>1999</year></entry>',
        )

        expect(entry.name).to eq("Gamma")
        expect(entry.year).to eq(1999)
        expect(entry.id).to eq("z9")
        expect(entry.to_xml).to include('<entry id="z9">')
        expect(entry.to_xml).not_to include("CT_entry")
      end
    end
  end
end
