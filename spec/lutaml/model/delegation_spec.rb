# spec/lutaml/model/delegation_spec.rb
require "spec_helper"
require "lutaml/model"

module Delegation
  class Glaze < Lutaml::Model::Serializable
    attribute :color, Lutaml::Model::Type::String
    attribute :finish, Lutaml::Model::Type::String
  end

  class Ceramic < Lutaml::Model::Serializable
    attribute :type, Lutaml::Model::Type::String
    attribute :glaze, Glaze

    json do
      map "type", to: :type
      map "color", to: :color, delegate: :glaze
      map "finish", to: :finish, delegate: :glaze
    end

    yaml do
      map "type", to: :type
      map "color", to: :color, delegate: :glaze
      map "finish", to: :finish, delegate: :glaze
    end

    toml do
      map "type", to: :type
      map "color", to: :color, delegate: :glaze
      map "finish", to: :finish, delegate: :glaze
    end

    xml do
      root "delegation"
      map_element "type", to: :type
      map_element "color", to: :color, delegate: :glaze
      map_element "finish", to: :finish, delegate: :glaze
    end
  end
end

RSpec.describe Delegation do
  let(:yaml_data) {
    <<~YAML
      type: Vase
      color: Blue
      finish: Glossy
    YAML
  }

  let(:delegation) { Delegation::Ceramic.from_yaml(yaml_data) }

  it "deserializes from YAML with delegation" do
    expect(delegation.type).to eq("Vase")
    expect(delegation.glaze.color).to eq("Blue")
    expect(delegation.glaze.finish).to eq("Glossy")
  end

  it "serializes to YAML with delegation" do
    expected_yaml = <<~YAML
      ---
      type: Vase
      color: Blue
      finish: Glossy
    YAML
    expect(delegation.to_yaml.strip).to eq(expected_yaml.strip)
  end

  it "serializes to JSON with delegation and filtering" do
    expected_json = {
      type: "Vase",
      color: "Blue",
    }.to_json

    expect(JSON.parse(delegation.to_json(only: [:type, :color]))).to eq(JSON.parse(expected_json))
  end

  it "serializes to JSON with pretty formatting" do
    expected_pretty_json = {
      "type": "Vase",
      "color": "Blue"
    }.to_json

    expect(delegation.to_json(only: [:type, :color], pretty: true).strip).to eq(expected_pretty_json.strip)
  end

  it "serializes to XML with pretty formatting" do
    expected_pretty_xml = <<-XML
<delegation>
  <type>Vase</type>
  <color>Blue</color>
  <finish>Glossy</finish>
</delegation>
    XML

    expect(delegation.to_xml(pretty: true).strip).to be_equivalent_to(expected_pretty_xml.strip)
  end

  it "does not provide XML declaration if no declaration option provided" do
    xml_data = delegation.to_xml(pretty: true)
    expect(xml_data).not_to include("<?xml")
  end

  it "provides XML declaration with default version if declaration: true option provided" do
    xml_data = delegation.to_xml(pretty: true, declaration: true)
    expect(xml_data).to include('<?xml version="1.0"?>')
  end

  it "provides XML declaration with specified version if declaration: '1.1' option provided" do
    xml_data = delegation.to_xml(pretty: true, declaration: "1.1")
    expect(xml_data).to include('<?xml version="1.1"?>')
  end

  it "provides XML declaration without encoding if encoding option not provided" do
    xml_data = delegation.to_xml(pretty: true, declaration: true)
    expect(xml_data).to include('<?xml version="1.0"?>')
    expect(xml_data).not_to include("encoding=")
  end

  it "provides XML declaration with UTF-8 encoding if encoding: true option provided" do
    xml_data = delegation.to_xml(pretty: true, declaration: true, encoding: true)
    expect(xml_data).to include('<?xml version="1.0" encoding="UTF-8"?>')
  end

  it "provides XML declaration with specified encoding if encoding: 'ASCII' option provided" do
    xml_data = delegation.to_xml(pretty: true, declaration: true, encoding: "ASCII")
    expect(xml_data).to include('<?xml version="1.0" encoding="ASCII"?>')
  end

  it "sets the default namespace of <delegation>" do
    class Delegation::Ceramic
      xml do
        root "delegation"
        namespace "https://example.com/delegation/1.2"
        map_element "type", to: :type
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    delegation_class = Delegation::Ceramic
    delegation = delegation_class.from_yaml(yaml_data)
    xml_data = delegation.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<delegation xmlns="https://example.com/delegation/1.2">')
  end

  it "sets the namespace of <delegation> with a prefix" do
    class Delegation::Ceramic
      xml do
        root "delegation"
        namespace "https://example.com/delegation/1.2", "del"
        map_element "type", to: :type
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end
    delegation_class = Delegation::Ceramic
    delegation = delegation_class.from_yaml(yaml_data)
    xml_data = delegation.to_xml(pretty: true, declaration: true, encoding: "UTF-8")

    expect(xml_data).to include('<del:delegation xmlns:del="https://example.com/delegation/1.2">')
  end

  it "sets the namespace of a particular element inside Ceramic" do
    class Delegation::Ceramic
      xml do
        root "delegation"
        map_element "type", to: :type, namespace: "https://example.com/type/1.2", prefix: "type"
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    delegation_class = Delegation::Ceramic

    delegation = delegation_class.from_yaml(yaml_data)
    xml_data = delegation.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<delegation xmlns:type="https://example.com/type/1.2">')
    expect(xml_data).to include("<type:type>Vase</type:type>")
  end

  it "sets the namespace of <delegation> and also a particular element inside using :inherit" do
    class Delegation::Ceramic
      xml do
        root "delegation"
        namespace "https://example.com/delegation/1.2", "del"
        map_element "type", to: :type #, namespace: :inherit
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    delegation_class = Delegation::Ceramic
    delegation = delegation_class.from_yaml(yaml_data)
    xml_data = delegation.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<del:delegation xmlns:del="https://example.com/delegation/1.2">')
    expect(xml_data).to include("<del:type>Vase</del:type>")
  end

  it "sets the namespace of a particular attribute inside <delegation>" do
    class Delegation::Ceramic
      attribute :date,  Lutaml::Model::Type::Date

      xml do
        root "delegation"
        map_attribute "date", to: :date, namespace: "https://example.com/delegation/1.2", prefix: "del"
        map_element "type", to: :type
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    delegation_class = Delegation::Ceramic
    delegation = delegation_class.new(type: "Vase", glaze: Delegation::Glaze.new(color: "Blue", finish: "Glossy"), date: "2024-06-08")
    xml_data = delegation.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<delegation xmlns:del="https://example.com/delegation/1.2" del:date="2024-06-08">')
  end

  it "sets the namespace of <delegation> and also a particular attribute inside using :inherit" do
    class Delegation::Ceramic
      attribute :date,  Lutaml::Model::Type::Date

      xml do
        root "delegation"
        namespace "https://example.com/delegation/1.1", "del1"
        map_attribute "date", to: :date, namespace: "https://example.com/delegation/1.2", prefix: "del2"
        map_element "type", to: :type #, namespace: :inherit
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    delegation_class = Delegation::Ceramic
    delegation = delegation_class.new(type: "Vase", glaze: Delegation::Glaze.new(color: "Blue", finish: "Glossy"), date: "2024-06-08")
    xml_data = delegation.to_xml(pretty: true, declaration: true, encoding: "UTF-8")
    expect(xml_data).to include('<del1:delegation xmlns:del1="https://example.com/delegation/1.1" xmlns:del2="https://example.com/delegation/1.2" del2:date="2024-06-08">')
    expect(xml_data).to include("<del1:type>Vase</del1:type>")
  end

  it "raises an error when namespaces are used with Ox" do
    class Delegation::Ceramic
      xml do
        root "delegation"
        namespace "https://example.com/delegation/1.2", "del"
        map_element "type", to: :type
        map_element "color", to: :color, delegate: :glaze
        map_element "finish", to: :finish, delegate: :glaze
      end
    end

    delegation_class = Delegation::Ceramic
    delegation = delegation_class.from_yaml(yaml_data)
    allow(Lutaml::Model::Config).to receive(:xml_adapter).and_return(Lutaml::Model::XmlAdapter::OxDocument)

    expect { delegation.to_xml(pretty: true, declaration: true, encoding: "UTF-8") }.to raise_error("Namespaces are not supported with the Ox adapter.")
  end
end
