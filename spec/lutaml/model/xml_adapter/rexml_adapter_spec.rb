require "spec_helper"
require "rexml/document"
require_relative "../../../../lib/lutaml/model/xml/rexml_adapter"

RSpec.describe Lutaml::Model::Xml::RexmlAdapter do
  let(:xml_string) do
    <<~XML
      <root xmlns="http://example.com/default" xmlns:prefix="http://example.com/prefixed">
        <prefix:child attr="value" prefix:attr="prefixed_value">Text</prefix:child>
      </root>
    XML
  end

  let(:document) { described_class.parse(xml_string) }

  context "when parsing XML with namespaces" do
    let(:child) { document.root.children.first }

    it "parses the root element with default namespace" do
      expect(document.root.name).to eq("root")
      expect(document.root.namespace.uri).to eq("http://example.com/default")
      expect(document.root.namespace.prefix).to be_nil
    end

    it "parses child element with prefixed namespace" do
      expect(child.name).to eq("prefix:child")
      expect(child.namespace.uri).to eq("http://example.com/prefixed")
      expect(child.namespace.prefix).to eq("prefix")
    end

    it "parses attributes with and without namespaces" do
      expect(child.attributes["attr"].value).to eq("value")
      expect(child.attributes["attr"].namespace).to be_nil
      expect(child.attributes["prefix:attr"].value).to eq("prefixed_value")
      expect(child.attributes["prefix:attr"].namespace).to eq("http://example.com/prefixed")
      expect(child.attributes["prefix:attr"].namespace_prefix).to eq("prefix")
    end
  end

  context "when serializing to XML" do
    it "produces XML output with correct structure" do
      xml_output = document.to_xml

      # REXML's to_xml returns pretty-printed XML
      # Basic structure validation
      expect(xml_output).to include("<root")
      expect(xml_output).to include("</root>")
      expect(xml_output).to include("prefix:child")
      expect(xml_output).to include("attr=\"value\"")
      expect(xml_output).to include("prefix:attr=\"prefixed_value\"")
      expect(xml_output).to include("Text")
    end
  end

  context "when parsing malformed XML" do
    it "raises ParseException for unclosed tags" do
      malformed_xml = "<root><child>Text"
      expect do
        described_class.parse(malformed_xml)
      end.to raise_error(REXML::ParseException, /Malformed XML/)
    end

    it "raises ParseException for mismatched closing tags" do
      malformed_xml = "<root><child>Text</wrong></root>"
      expect do
        described_class.parse(malformed_xml)
      end.to raise_error(REXML::ParseException, /Malformed XML/)
    end

    it "raises ParseException for invalid XML content" do
      invalid_xml = "not xml at all"
      expect do
        described_class.parse(invalid_xml)
      end.to raise_error(REXML::ParseException, /Malformed XML/)
    end

    it "raises ParseException with descriptive message" do
      malformed_xml = "<root"
      expect do
        described_class.parse(malformed_xml)
      end.to raise_error(REXML::ParseException) do |error|
        expect(error.message).to include("Unable to parse")
        expect(error.message).to include("invalid or incomplete")
      end
    end
  end
end
