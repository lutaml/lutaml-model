# spec/ceramic_spec.rb
require "spec_helper"
require_relative "fixtures/ceramic"
require_relative "fixtures/glaze"

# This tests against `delegate`
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

    expect(ceramic.to_xml(pretty: true).strip).to be_equivalent_to(expected_pretty_xml.strip)
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

  it "sets the default namespace of <ceramic>" do
    ceramic_class = Class.new(Ceramic) do
      xml do
        root "ceramic"
        namespace "https://example.com/ceramic/1.2"
        map_element "type", to: :type
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    ceramic = ceramic_class.from_yaml(yaml_data)
    xml_data = ceramic.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<ceramic xmlns="https://example.com/ceramic/1.2">')
  end

  it "sets the namespace of <ceramic> with a prefix" do
    ceramic_class = Class.new(Ceramic) do
      xml do
        root "ceramic"
        namespace "https://example.com/ceramic/1.2", prefix: "cera"
        map_element "type", to: :type
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    ceramic = ceramic_class.from_yaml(yaml_data)
    xml_data = ceramic.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<cera:ceramic xmlns:cera="https://example.com/ceramic/1.2">')
  end

  it "sets the namespace of a particular element inside Ceramic" do
    ceramic_class = Class.new(Ceramic) do
      xml do
        root "ceramic"
        map_element "type", to: :type, namespace: "https://example.com/type/1.2", prefix: "type"
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    ceramic = ceramic_class.from_yaml(yaml_data)
    xml_data = ceramic.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<ceramic xmlns:type="https://example.com/type/1.2">')
    expect(xml_data).to include("<type:type>Vase</type:type>")
  end

  it "sets the namespace of <ceramic> and also a particular element inside using :inherit" do
    ceramic_class = Class.new(Ceramic) do
      xml do
        root "ceramic"
        namespace "https://example.com/ceramic/1.2", prefix: "cera"
        map_element "type", to: :type, namespace: :inherit
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    ceramic = ceramic_class.from_yaml(yaml_data)
    xml_data = ceramic.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<cera:ceramic xmlns:cera="https://example.com/ceramic/1.2">')
    expect(xml_data).to include("<cera:type>Vase</cera:type>")
  end

  it "sets the namespace of a particular attribute inside <ceramic>" do
    ceramic_class = Class.new(Ceramic) do
      xml do
        root "ceramic"
        map_attribute "date", to: :date, namespace: "https://example.com/ceramic/1.2", prefix: "cera"
        map_element "type", to: :type
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    ceramic = ceramic_class.new(type: "Vase", glaze: Glaze.new(color: "Blue", finish: "Glossy"), date: "2024-06-08")
    xml_data = ceramic.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<ceramic xmlns:cera="https://example.com/ceramic/1.2" cera:date="2024-06-08">')
  end

  it "sets the namespace of <ceramic> and also a particular attribute inside using :inherit" do
    ceramic_class = Class.new(Ceramic) do
      xml do
        root "ceramic"
        namespace "https://example.com/ceramic/1.1", prefix: "cera1"
        map_attribute "date", to: :date, namespace: "https://example.com/ceramic/1.2", prefix: "cera2"
        map_element "type", to: :type, namespace: :inherit
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    ceramic = ceramic_class.new(type: "Vase", glaze: Glaze.new(color: "Blue", finish: "Glossy"), date: "2024-06-08")
    xml_data = ceramic.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<cera1:ceramic xmlns:cera1="https://example.com/ceramic/1.1" xmlns:cera2="https://example.com/ceramic/1.2" cera2:date="2024-06-08">')
    expect(xml_data).to include("<cera1:type>Vase</cera1:type>")
  end

  it "raises an error when namespaces are used with Ox" do
    ceramic_class = Class.new(Ceramic) do
      xml do
        root "ceramic"
        namespace "https://example.com/ceramic/1.2", prefix: "cera"
        map_element "type", to: :type
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    ceramic = ceramic_class.from_yaml(yaml_data)
    allow(Lutaml::Model::Config).to receive(:xml_adapter).and_return(Lutaml::Model::XmlAdapter::OxDocument)

    expect { ceramic.to_xml(pretty: true, declaration: true, encoding: "UTF-8") }.to raise_error("Namespaces are not supported with the Ox adapter.")
  end
end
