# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../../../spec_helper"
require "lutaml/xml/schema/xsd"

# #1051: an xs:import without a namespace attribute is legal
# (XSD 1.0 §3.13.2 — it imports a schema document with no target
# namespace). The schema walk read the attribute store unguarded, so
# a follow-up schema document carrying such an import crashed the
# parse with "undefined method 'value' for nil".
RSpec.describe "Xsd import without a namespace attribute" do
  let(:dir) { Dir.mktmpdir }

  before do
    File.write(File.join(dir, "a.xsd"), <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:import namespace="http://www.w3.org/XML/1998/namespace" schemaLocation="b.xsd"/>
        <xs:element name="root"/>
      </xs:schema>
    XSD
    File.write(File.join(dir, "b.xsd"), <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:import schemaLocation="c.xsd"/>
        <xs:attribute name="lang" type="xs:language"/>
      </xs:schema>
    XSD
    File.write(File.join(dir, "c.xsd"), <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="helper"/>
      </xs:schema>
    XSD
  end

  after { FileUtils.remove_entry(dir) }

  it "parses the whole chain" do
    parsed = Lutaml::Xml::Schema::Xsd.parse(
      File.read(File.join(dir, "a.xsd")),
      location: dir,
    )

    expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
    expect(parsed.imports.first.schema_path).to eq("b.xsd")
    expect(parsed.import.first).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
  end

  it "keeps the namespace-less import unnamed" do
    parsed = Lutaml::Xml::Schema::Xsd.parse(
      <<~XSD,
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:import schemaLocation="c.xsd"/>
        </xs:schema>
      XSD
      location: dir,
    )

    expect(parsed.imports.first.namespace).to be_nil
  end
end
