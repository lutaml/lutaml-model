# frozen_string_literal: true

require "spec_helper"

# lutaml/lutaml-model#1222: the XSD 1.1 versioning markers
# (vc:minVersion / vc:maxVersion, XSD 1.1 §C.1) dropped at parse and
# roundtrip — the engine tier compiles the 1.1-only constructs
# (alternatives, openContent, assertions) only when the marker
# survives to compilation, so the loss gated the CTA family through
# the roundtrip compile.
RSpec.describe "the vc: versioning markers on XSD Schema (#1222)" do
  let(:schema_xml) do
    <<~XSD
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
        xmlns:vc="http://www.w3.org/2007/XMLSchema-versioning"
        vc:minVersion="1.1">
        <xs:element name="doc">
          <xs:complexType>
            <xs:sequence><xs:element name="a"/></xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
  end

  it "parses vc:minVersion into the model" do
    schema = Lutaml::Xml::Schema::Xsd.parse(schema_xml)

    expect(schema.vc_min_version).to eq("1.1")
  end

  it "roundtrips vc:minVersion back into the markup" do
    schema = Lutaml::Xml::Schema::Xsd.parse(schema_xml)
    out = schema.to_xml

    expect(out).to include("minVersion=\"1.1\"")
    expect(out).to include("http://www.w3.org/2007/XMLSchema-versioning")
  end

  it "carries vc:maxVersion the same way" do
    schema = Lutaml::Xml::Schema::Xsd.parse(
      schema_xml.gsub('vc:minVersion="1.1"', 'vc:maxVersion="1.0"'),
    )

    expect(schema.vc_max_version).to eq("1.0")
    expect(schema.to_xml).to include("maxVersion=\"1.0\"")
  end
end
