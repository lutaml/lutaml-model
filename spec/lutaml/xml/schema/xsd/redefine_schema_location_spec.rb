# frozen_string_literal: true

require_relative "../../../../spec_helper"
require "open3"
require "lutaml/xml/schema/xsd"

# #1042: the XSD schema-object classes map the plain `schemaLocation`
# attribute — an XSD attribute on xs:redefine, not xsi:schemaLocation.
# The class used to warn about its own mapping ("handled by default"),
# and the engine's raw xsi capture then re-emitted the value as
# xsi:schemaLocation beside the mapped attribute.
RSpec.describe "Xsd::Redefine schemaLocation" do
  let(:xsd) do
    <<~XSD
      <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <xsd:redefine schemaLocation="base.xsd">
          <xsd:group name="g">
            <xsd:choice><xsd:element name="e1"/></xsd:choice>
          </xsd:group>
        </xsd:redefine>
      </xsd:schema>
    XSD
  end

  it "reads schemaLocation into schema_path" do
    doc = Lutaml::Xml::Schema::Xsd.parse(xsd)

    expect(doc.redefine.first.schema_path).to eq("base.xsd")
  end

  it "round-trips it as the plain attribute without an xsi copy" do
    xml = Lutaml::Xml::Schema::Xsd.parse(xsd).to_xml

    expect(xml).to include('schemaLocation="base.xsd"')
    expect(xml).not_to include("xsi:schemaLocation")
  end

  it "does not warn while defining its own mapping" do
    probe = 'require "lutaml/model"; require "lutaml/xml/schema/xsd"; ' \
            "Lutaml::Xml::Schema::Xsd::Redefine"

    _out, err, status = Open3.capture3(RbConfig.ruby, "-I", "lib", "-e", probe)

    expect(status).to be_success, err
    expect(err).not_to include("handled by default")
  end

  it "still captures xsi:schemaLocation on models that do not map it" do
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      xml do
        element "r"
        map_attribute "name", to: :name
      end
    end
    stub_const("AutoSchemaLocationModel", model)

    parsed = AutoSchemaLocationModel.from_xml(
      '<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' \
      'name="n" xsi:schemaLocation="urn:a a.xsd"/>',
    )

    expect(parsed.raw_schema_location).to eq("urn:a a.xsd")
  end
end
