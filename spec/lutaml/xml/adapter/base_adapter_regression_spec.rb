# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"
require "lutaml/xml"
require "lutaml/xml/adapter/nokogiri_adapter"
require "lutaml/xml/adapter/ox_adapter"
require "lutaml/xml/adapter/oga_adapter"
require "lutaml/xml/adapter/rexml_adapter"

# Regression tests for BaseAdapter refactoring.
# Each test guards a specific bug fix to prevent re-introduction.
# Run against all 4 adapters to ensure consistent behavior.
RSpec.shared_examples "base adapter regressions" do |adapter_class|
  let(:adapter) { adapter_class }

  describe "CDATA preservation in mixed content" do
    let(:xml_with_cdata) do
      "<root><![CDATA[Hello]]><b>world</b><![CDATA[!]]></root>"
    end

    it "preserves CDATA wrapping for mixed content string nodes" do
      doc = adapter.parse(xml_with_cdata)
      output = doc.to_xml

      expect(output).to include("<![CDATA[Hello]]>")
      expect(output).to include("<![CDATA[!]]>")
    end
  end

  describe "XML comment preservation in serialization" do
    let(:xml_with_comment) do
      "<root><a/><!--middle comment--><b/></root>"
    end

    it "preserves comments during round-trip" do
      doc = adapter.parse(xml_with_comment)
      output = doc.to_xml

      expect(output).to include("<!--middle comment-->")
    end
  end

  describe "processing instructions do not affect text shape" do
    let(:xml_with_pi_and_text) do
      "<root>hello<?pi data?></root>"
    end

    let(:xml_with_only_pi) do
      "<root><?pi data?></root>"
    end

    it "returns text as a string when PI is alongside text" do
      doc = adapter.parse(xml_with_pi_and_text)

      # text should be a string, not an array —
      # PIs should not make plain text look like mixed content
      expect(doc.text).to be_a(String)
      expect(doc.text).to eq("hello")
    end

    it "returns empty string for text when element has only PI" do
      doc = adapter.parse(xml_with_only_pi)

      expect(doc.text).to be_a(String)
      expect(doc.text).to eq("")
    end
  end

  describe "processing instructions excluded from parse_element" do
    let(:xml_with_pi) do
      "<root><?foo ignored?><bar>content</bar></root>"
    end

    it "does not include PI in elements hash" do
      doc = adapter.parse(xml_with_pi)
      hash = doc.to_h

      elements = hash["elements"]
      expect(elements).to have_key("bar")
      # PI should not appear as an element key
      expect(elements.keys).not_to include("foo")
    end
  end

  describe "ASCII-8BIT encoding round-trip" do
    let(:binary_xml) { "<root>\xC2\xB5</root>".b }

    it "round-trips binary-tagged UTF-8 content without encoding error" do
      doc = adapter.parse(binary_xml)

      expect { doc.to_xml }.not_to raise_error
      expect(doc.to_xml).to include("\u00B5") # micro sign
    end

    it "does not use ASCII-8BIT as output encoding" do
      doc = adapter.parse(binary_xml)
      output = doc.to_xml

      expect(output.encoding).not_to eq(Encoding::ASCII_8BIT)
    end
  end

  describe "namespaced_attr_name helper arity" do
    it "resolves single-arg namespaced_attr_name from AdapterHelpers" do
      # This verifies the AdapterHelpers version (single Moxml attribute arg)
      # is accessible and not shadowed by a 2-arg def self. method
      expect(adapter).to respond_to(:namespaced_attr_name)

      # The method should accept 1 argument (a Moxml attribute object)
      method = adapter.method(:namespaced_attr_name)
      expect(method.arity).to eq(1)
    end
  end

  describe "XmlParser helper methods are private" do
    it "does not expose normalize_xml_for_parse as a public class method" do
      expect(adapter.public_methods).not_to include(:normalize_xml_for_parse)
    end

    it "does not expose parse_with_moxml as a public class method" do
      expect(adapter.public_methods).not_to include(:parse_with_moxml)
    end

    it "does not expose raise_empty_document_error as a public class method" do
      expect(adapter.public_methods).not_to include(:raise_empty_document_error)
    end

    it "exposes parse as a public class method" do
      expect(adapter.public_methods).to include(:parse)
    end
  end
end

RSpec.describe Lutaml::Xml::Adapter::BaseAdapter do
  context "with NokogiriAdapter" do
    it_behaves_like "base adapter regressions", Lutaml::Xml::Adapter::NokogiriAdapter
  end

  context "with OxAdapter" do
    it_behaves_like "base adapter regressions", Lutaml::Xml::Adapter::OxAdapter
  end

  context "with OgaAdapter" do
    it_behaves_like "base adapter regressions", Lutaml::Xml::Adapter::OgaAdapter
  end

  context "with RexmlAdapter" do
    it_behaves_like "base adapter regressions", Lutaml::Xml::Adapter::RexmlAdapter
  end
end
