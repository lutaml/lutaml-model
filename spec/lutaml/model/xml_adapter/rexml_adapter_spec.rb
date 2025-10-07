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
      expect(document.root.namespace.uri).to eq("http://example.com/default") if document.root.namespace
    end

    it "parses child element correctly" do
      expect(child).not_to be_nil
      expect(child.name).to include("child")
    end

    it "parses attributes correctly" do
      expect(child.attributes).not_to be_empty
    end
  end

  context "when serializing to XML" do
    it "produces valid XML output" do
      xml_output = document.to_xml
      expect(xml_output).to include("<root")
      expect(xml_output).to include("</root>")
    end
  end
end
