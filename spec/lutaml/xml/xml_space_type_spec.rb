# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Xml::W3c::XmlSpaceType do
  describe ".cast" do
    it "returns 'preserve' for valid value 'preserve'" do
      result = described_class.cast("preserve")
      expect(result).to eq("preserve")
    end

    it "returns 'default' for valid value 'default'" do
      result = described_class.cast("default")
      expect(result).to eq("default")
    end

    it "returns nil when value is nil" do
      result = described_class.cast(nil)
      expect(result).to be_nil
    end

    it "raises ArgumentError for invalid value" do
      expect { described_class.cast("invalid") }.to raise_error(
        ArgumentError,
        "xml:space must be 'default' or 'preserve'",
      )
    end

    it "raises ArgumentError for empty string" do
      expect { described_class.cast("") }.to raise_error(
        ArgumentError,
        "xml:space must be 'default' or 'preserve'",
      )
    end

    it "raises ArgumentError for mixed case values" do
      expect { described_class.cast("PRESERVE") }.to raise_error(
        ArgumentError,
        "xml:space must be 'default' or 'preserve'",
      )
      expect { described_class.cast("Default") }.to raise_error(
        ArgumentError,
        "xml:space must be 'default' or 'preserve'",
      )
    end
  end
end

RSpec.describe "xml:space attribute with nil values" do
  # Test model with optional xml:space attribute
  class OptionalXmlSpaceModel < Lutaml::Model::Serializable
    attribute :content, :string
    attribute :space, Lutaml::Xml::W3c::XmlSpaceType

    xml do
      element "element"
      map_content to: :content
      map_attribute "space", to: :space
    end
  end

  after do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  describe "Issue: xml:space attribute is optional" do
    it "parses element without xml:space attribute" do
      xml_in = "<element>Some content</element>"
      model = OptionalXmlSpaceModel.from_xml(xml_in)
      expect(model.content).to eq("Some content")
      expect(model.space).to be_nil
    end

    it "parses element with xml:space attribute" do
      xml_in = '<element xml:space="preserve">Some content</element>'
      model = OptionalXmlSpaceModel.from_xml(xml_in)
      expect(model.content).to eq("Some content")
      expect(model.space).to eq("preserve")
    end

    it "serializes model without xml:space value" do
      model = OptionalXmlSpaceModel.new(content: "Some content", space: nil)
      xml = model.to_xml
      expect(xml).to eq("<element>Some content</element>")
      expect(xml).not_to include("xml:space")
    end

    it "serializes model with xml:space value" do
      model = OptionalXmlSpaceModel.new(content: "Some content",
                                        space: "preserve")
      xml = model.to_xml
      expect(xml).to include('xml:space="preserve"')
    end

    it "round-trips element without xml:space attribute" do
      xml_in = "<element>Some content</element>"
      model = OptionalXmlSpaceModel.from_xml(xml_in)
      xml_out = model.to_xml
      expect(xml_out).to eq("<element>Some content</element>")
    end

    it "round-trips element with xml:space attribute" do
      xml_in = '<element xml:space="preserve">Some content</element>'
      model = OptionalXmlSpaceModel.from_xml(xml_in)
      xml_out = model.to_xml
      expect(xml_out).to include('xml:space="preserve"')
      expect(xml_out).to include("Some content")
    end
  end
end

RSpec.describe "Self-referential models" do
  # Self-referential model for testing circular reference handling
  class TreeNode < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :children, TreeNode, collection: true

    xml do
      element "node"
      map_attribute "name", to: :name
      map_element "node", to: :children
    end
  end

  after do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  describe "Issue: Self-referential models cause stack overflow" do
    it "parses self-referential model without stack overflow" do
      xml_in = '<node name="root"><node name="child1"></node><node name="child2"></node></node>'
      model = TreeNode.from_xml(xml_in)
      expect(model.name).to eq("root")
      expect(model.children.size).to eq(2)
      expect(model.children[0].name).to eq("child1")
      expect(model.children[1].name).to eq("child2")
    end

    it "serializes self-referential model to YAML without stack overflow" do
      model = TreeNode.new(name: "root", children: [
                             TreeNode.new(name: "child1", children: []),
                             TreeNode.new(name: "child2", children: []),
                           ])
      yaml = model.to_yaml
      expect(yaml).to include("root")
      expect(yaml).to include("child1")
      expect(yaml).to include("child2")
    end

    it "serializes self-referential model to JSON without stack overflow" do
      model = TreeNode.new(name: "root", children: [
                             TreeNode.new(name: "child1", children: []),
                             TreeNode.new(name: "child2", children: []),
                           ])
      json = model.to_json
      expect(json).to include("root")
      expect(json).to include("child1")
      expect(json).to include("child2")
    end
  end
end
