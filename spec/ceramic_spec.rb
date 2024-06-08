# spec/ceramic_spec.rb
require "spec_helper"
require_relative "fixtures/ceramic"
require_relative "fixtures/glaze"

RSpec.describe Ceramic do
  let(:yaml_data) {
    <<~YAML
      type: Vase
      color: Blue
      finish: Glossy
    YAML
  }

  let(:ceramic) { Ceramic.from_yaml(yaml_data) }

  it "deserializes from YAML with delegation" do
    expect(ceramic.type).to eq("Vase")
    expect(ceramic.glaze.color).to eq("Blue")
    expect(ceramic.glaze.finish).to eq("Glossy")
  end

  it "serializes to YAML with delegation" do
    expected_yaml = <<~YAML
      type: Vase
      color: Blue
      finish: Glossy
    YAML
    expect(ceramic.to_yaml.strip).to eq(expected_yaml.strip)
  end

  it "serializes to JSON with delegation and filtering" do
    expected_json = {
      type: "Vase",
      color: "Blue",
    }.to_json

    expect(JSON.parse(ceramic.to_json(only: [:type, :color]))).to eq(JSON.parse(expected_json))
  end

  it "serializes to JSON with pretty formatting" do
    expected_pretty_json = <<-JSON
{
  "type": "Vase",
  "color": "Blue"
}
    JSON

    expect(ceramic.to_json(only: [:type, :color], pretty: true).strip).to eq(expected_pretty_json.strip)
  end

  it "serializes to XML with pretty formatting" do
    expected_pretty_xml = <<-XML
<ceramic>
  <type>Vase</type>
  <color>Blue</color>
  <finish>Glossy</finish>
</ceramic>
    XML

    expect(ceramic.to_xml(pretty: true).strip).to eq(expected_pretty_xml.strip)
  end

  it "does not provide XML declaration if no declaration option provided" do
    xml_data = ceramic.to_xml(pretty: true)
    expect(xml_data).not_to include("<?xml")
  end

  it "provides XML declaration with default version if declaration: true option provided" do
    xml_data = ceramic.to_xml(pretty: true, declaration: true)
    expect(xml_data).to include('<?xml version="1.0"?>')
  end

  it "provides XML declaration with specified version if declaration: '1.1' option provided" do
    xml_data = ceramic.to_xml(pretty: true, declaration: "1.1")
    expect(xml_data).to include('<?xml version="1.1"?>')
  end

  it "provides XML declaration without encoding if encoding option not provided" do
    xml_data = ceramic.to_xml(pretty: true, declaration: true)
    expect(xml_data).to include('<?xml version="1.0"?>')
    expect(xml_data).not_to include("encoding=")
  end

  it "provides XML declaration with UTF-8 encoding if encoding: true option provided" do
    xml_data = ceramic.to_xml(pretty: true, declaration: true, encoding: true)
    expect(xml_data).to include('<?xml version="1.0" encoding="UTF-8"?>')
  end

  it "provides XML declaration with specified encoding if encoding: 'ASCII' option provided" do
    xml_data = ceramic.to_xml(pretty: true, declaration: true, encoding: "ASCII")
    expect(xml_data).to include('<?xml version="1.0" encoding="ASCII"?>')
  end
end
