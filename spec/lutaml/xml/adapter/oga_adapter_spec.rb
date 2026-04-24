require "spec_helper"
require "oga"
require_relative "../../../../lib/lutaml/xml/adapter/oga_adapter"

RSpec.describe Lutaml::Xml::Adapter::OgaAdapter, :oga_adapter do
  let(:xml_string) do
    <<~XML
      <root xmlns="http://example.com/default" xmlns:prefix="http://example.com/prefixed">
        <prefix:child attr="value" prefix:attr="prefixed_value">Text</prefix:child>
      </root>
    XML
  end

  let(:document) { described_class.parse(xml_string) }

  context "when parsing XML with namespaces" do
    let(:child) { document.root.element_children.first }

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
      child = doc_with_default.root.element_children.first
      expect(child.name).to eq("child")
      expect(child.namespace.uri).to eq("http://example.com/default")
      expect(child.namespace.prefix).to be_nil
    end

    it "applies default namespace to all unprefixed elements" do
      children = doc_with_default.root.element_children
      children.each do |child|
        expect(child.namespace.uri).to eq("http://example.com/default")
        expect(child.namespace.prefix).to be_nil
      end
    end
  end

  context "when parsing XML with comments" do
    let(:xml_with_comment) do
      <<~XML
        <root>
          <child>text</child>
          <!-- a comment -->
        </root>
      XML
    end

    let(:doc_with_comment) { described_class.parse(xml_with_comment) }

    let(:moxml_comment) do
      ctx = Moxml.new(:oga)
      doc = ctx.parse(xml_with_comment)
      doc.root.children.find { |n| n.is_a?(Moxml::Comment) }
    end

    it "returns 'comment' for Moxml::Comment nodes via name_of" do
      expect(described_class.name_of(moxml_comment)).to eq("comment")
    end

    it "parses comment nodes with the correct node type" do
      comment = doc_with_comment.root.children.find(&:comment?)

      expect(comment).not_to be_nil
      expect(comment.name).to eq("comment")
      expect(comment.node_type).to eq(:comment)
      expect(comment.text).to eq(" a comment ")
    end

    it "serializes parsed comments back to XML comments" do
      expect(doc_with_comment.root.to_xml).to include("<!-- a comment -->")
    end
  end

  context "when generating XML with namespaces" do
    it "generates XML with namespaces correctly" do
      xml_output = document.root.to_xml
      parsed_output = Moxml::Adapter::Oga.parse(xml_output)

      root = parsed_output.root
      expect(root.name).to eq("root")
      expect(root.namespace.uri).to eq("http://example.com/default")

      child = root.children.find { |n| n.is_a?(Moxml::Element) }
      expect(described_class.prefixed_name_of(child)).to eq("prefix:child")
      expect(child.namespace.uri).to eq("http://example.com/prefixed")
      unprefixed_attr = child.attributes.find { |attr| attr.name == "attr" }
      expect(unprefixed_attr.value).to eq("value")
      prefixed_attr = child.attributes.find do |attr|
        described_class.prefixed_name_of(attr) == "prefix:attr"
      end
      expect(prefixed_attr.value).to eq("prefixed_value")
    end
  end
end
