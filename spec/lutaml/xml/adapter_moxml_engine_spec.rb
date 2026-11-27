# frozen_string_literal: true

require "spec_helper"

# The #1224 completion on top of the deferred lane: the schema/builder
# surfaces construct Moxml contexts directly and must ask for the
# ENGINE, not the configured type (whose :moxml lane value is not a
# valid Moxml adapter name); the leptris plan fast-path gates must
# resolve through the deferred lane to its engine.
RSpec.describe "the deferred lane's engine resolution seams" do
  around do |example|
    saved = Lutaml::Model::Config.xml_adapter_type
    Lutaml::Model::Config.xml_adapter_type = :moxml
    example.run
  ensure
    Lutaml::Model::Config.xml_adapter_type = saved
  end

  it "answers the engine Moxml deploys through the adapter seam" do
    expect(Lutaml::Model::Config.xml_adapter.engine_adapter_class.name)
      .to eq("Lutaml::Xml::Adapter::LeptrisAdapter")
  end

  it "parses an XSD schema under the deferred lane" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:sequence>
            <xs:element name="a"/>
          </xs:sequence>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)

    expect(schema.complex_type.first.name).to eq("t")
  end

  it "keeps the leptris plan fast path under explicit :moxml selection" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      xml do
        element "probe"
        map_element "name", to: :name
      end
    end

    expect(klass.from_xml("<probe><name>x</name></probe>").name).to eq("x")
    expect(klass.new(name: "x").to_xml).to include("<name>x</name>")
  end

  it "names the engine for Moxml context construction" do
    expect(Lutaml::Xml.moxml_engine).to eq(Moxml::Config.default.adapter_name)
  end
end
