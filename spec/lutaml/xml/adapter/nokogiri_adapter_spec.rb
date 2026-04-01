require "spec_helper"
require "nokogiri"
require_relative "../../../../lib/lutaml/xml/adapter/nokogiri_adapter"

RSpec.describe Lutaml::Xml::Adapter::NokogiriAdapter do
  let(:xml_string) do
    <<-XML
      <root xmlns="http://example.com/default" xmlns:prefix="http://example.com/prefixed">
        <prefix:child attr="value" prefix:attr1="prefixed_value">Text</prefix:child>
      </root>
    XML
  end

  let(:document) { described_class.parse(xml_string) }

  context "when parsing XML with namespaces" do
    let(:child) { document.root.children[1] }

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
      expect(child.attributes["prefix:attr1"].value).to eq("prefixed_value")
      expect(child.attributes["prefix:attr1"].namespace).to eq("http://example.com/prefixed")
      expect(child.attributes["prefix:attr1"].namespace_prefix).to eq("prefix")
    end
  end

  context "when parsing elements in default namespace" do
    let(:xml_with_default_ns) do
      <<~XML
        <root xmlns="http://example.com/default">
          <child>Content</child>
          <another>More content</another>
        </root>
      XML
    end

    let(:doc_with_default) { described_class.parse(xml_with_default_ns) }

    it "treats unprefixed child elements as being in the default namespace" do
      children_elements = doc_with_default.root.children.reject do |c|
        c.name == "text"
      end
      child = children_elements.first
      expect(child.name).to eq("child")
      expect(child.namespace.uri).to eq("http://example.com/default")
      expect(child.namespace.prefix).to be_nil
    end

    it "applies default namespace to all unprefixed elements" do
      children = doc_with_default.root.children.reject { |c| c.name == "text" }
      children.each do |child|
        expect(child.namespace.uri).to eq("http://example.com/default")
        expect(child.namespace.prefix).to be_nil
      end
    end
  end

  context "when generating XML with namespaces" do
    it "generates XML with namespaces correctly" do
      xml_output = document.to_xml
      parsed_output = Nokogiri::XML(xml_output)

      root = parsed_output.root
      expect(root.name).to eq("root")
      expect(root.namespace.href).to eq("http://example.com/default")

      child = root.children[1]
      expect(child.name).to eq("child")
      expect(child.namespace.href).to eq("http://example.com/prefixed")
      expect(child.attributes["attr"].value).to eq("value")
      expect(child.attributes["attr1"].value).to eq("prefixed_value")
    end
  end

  describe "namespace declaration deduplication" do
    let(:schema_location_xml) do
      <<-XML
        <root xmlns="http://example.com/ns" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://example.com/ns http://example.com/schema.xsd">
          <child>content</child>
        </root>
      XML
    end

    it "does not produce duplicate xmlns declarations for xsi namespace" do
      parsed = described_class.parse(schema_location_xml)
      xml_output = parsed.to_xml

      # Count xmlns:xsi declarations - should be exactly 1
      xmlns_xsi_count = xml_output.scan("xmlns:xsi=").count
      expect(xmlns_xsi_count).to eq(1),
                                 "Expected exactly 1 xmlns:xsi declaration, got #{xmlns_xsi_count} in:\n#{xml_output}"
    end

    it "round-trips XML with schemaLocation correctly" do
      parsed = described_class.parse(schema_location_xml)
      xml_output = parsed.to_xml

      # Should preserve schemaLocation attribute
      expect(xml_output).to include("xsi:schemaLocation=")

      # Should have exactly one xmlns:xsi
      xmlns_xsi_count = xml_output.scan("xmlns:xsi=").count
      expect(xmlns_xsi_count).to eq(1)
    end
  end
end
