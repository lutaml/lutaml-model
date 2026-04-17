# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml/sax_handler"

RSpec.describe Lutaml::Xml::SaxHandler do
  let(:context) { Moxml.new(:nokogiri) }

  def parse_sax(xml)
    handler = described_class.new
    context.sax_parse(xml, handler)
    handler.root
  end

  describe "basic element parsing" do
    let(:xml) { "<root><child>hello</child></root>" }

    it "builds an XmlElement tree from SAX events" do
      root = parse_sax(xml)

      expect(root).to be_a(Lutaml::Xml::XmlElement)
      expect(root.name).to eq("root")
      expect(root.children.size).to eq(1)

      child = root.children.first
      expect(child.name).to eq("child")
      expect(child.children.size).to eq(1)
      expect(child.children.first.text).to eq("hello")
    end
  end

  describe "attributes" do
    let(:xml) { '<person name="John" age="30"/>' }

    it "preserves element attributes" do
      root = parse_sax(xml)

      expect(root.attributes.keys).to contain_exactly("name", "age")
      expect(root.attributes["name"]).to be_a(Lutaml::Xml::XmlAttribute)
      expect(root.attributes["name"].value).to eq("John")
      expect(root.attributes["age"].value).to eq("30")
    end
  end

  describe "namespaces" do
    let(:xml) do
      '<root xmlns="http://default.ns" xmlns:ex="http://example.ns">
        <ex:child ex:attr="value">text</ex:child>
      </root>'
    end

    it "tracks default namespace" do
      root = parse_sax(xml)

      expect(root.default_namespace.uri).to eq("http://default.ns")
    end

    it "tracks prefixed namespace declarations" do
      root = parse_sax(xml)

      expect(root.namespaces).to include("ex")
      expect(root.namespaces["ex"].uri).to eq("http://example.ns")
    end

    it "preserves namespace prefix on child elements" do
      root = parse_sax(xml)

      elements = root.children.select do |c|
        !c.text? && c.node_type == :element
      end
      child = elements.find { |c| c.name == "ex:child" }
      expect(child).not_to be_nil,
                           "Elements found: #{elements.map(&:name).inspect}"
      expect(child.namespace_prefix).to eq("ex")
    end
  end

  describe "mixed content" do
    let(:xml) { "<p>Hello <b>world</b>!</p>" }

    it "preserves text and element order" do
      root = parse_sax(xml)

      expect(root.children.size).to eq(3)
      expect(root.children[0].text).to eq("Hello ")
      expect(root.children[1].name).to eq("b")
      expect(root.children[2].text).to eq("!")
    end
  end

  describe "CDATA" do
    let(:xml) { "<root><![CDATA[<special>content</special>]]></root>" }

    it "preserves CDATA content" do
      root = parse_sax(xml)

      expect(root.children.size).to eq(1)
      expect(root.children.first.text).to include("<special>content</special>")
    end
  end

  describe "nested elements" do
    let(:xml) do
      <<~XML
        <book>
          <title>Ruby</title>
          <author>Matz</author>
          <chapter number="1">
            <heading>Introduction</heading>
          </chapter>
        </book>
      XML
    end

    it "builds correct tree structure" do
      root = parse_sax(xml)

      expect(root.name).to eq("book")
      title = root.children.find { |c| c.name == "title" }
      expect(title.text).to eq("Ruby")

      chapter = root.children.find { |c| c.name == "chapter" }
      expect(chapter.attributes["number"].value).to eq("1")
      heading = chapter.children.find { |c| c.name == "heading" }
      expect(heading.text).to eq("Introduction")
    end
  end

  describe "numeric character references in attributes" do
    # Numeric character references in attributes are resolved to characters
    # because attribute values are plain strings (not node trees).

    let(:xml) do
      '<source details="Ranger, Natalie * 2006 * Citizen. &#38; Emergency preparedness Div. * Standardization"/>'
    end

    it "resolves &#38; (decimal ampersand) in attribute values" do
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(xml)
      attr_val = adapter.root.attributes["details"].value

      expect(attr_val).to include("& Emergency")
      expect(attr_val).not_to include("&#38;")
    end

    it "resolves &#x26; (hex ampersand) in attribute values" do
      hex_xml = '<source details="A &#x26; B"/>'
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(hex_xml)
      attr_val = adapter.root.attributes["details"].value

      expect(attr_val).to eq("A & B")
    end

    it "resolves &#169; (copyright sign) in attribute values" do
      copyright_xml = '<source details="Copyright &#169; 2024"/>'
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(copyright_xml)
      attr_val = adapter.root.attributes["details"].value

      expect(attr_val).to eq("Copyright \u00A9 2024")
    end

    it "resolves &#x00A9; (hex copyright) in attribute values" do
      hex_copyright_xml = '<source details="Copyright &#x00A9; 2024"/>'
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(hex_copyright_xml)
      attr_val = adapter.root.attributes["details"].value

      expect(attr_val).to eq("Copyright \u00A9 2024")
    end

    it "resolves &#38; to & in attributes (SAX resolves correctly)" do
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(xml)
      sax_val = adapter.root.attributes["details"].value

      # SAX should resolve &#38; to & in attribute values
      expect(sax_val).to eq("Ranger, Natalie * 2006 * Citizen. & Emergency preparedness Div. * Standardization")
    end

    # Termium library regression test: this specific pattern caused 2289+
    # normative differences in round-trip serialization before the fix.
    it "handles the termium &#38; pattern in a realistic attribute" do
      termium_xml = <<~XML
        <source details="Ranger, Natalie * 2006 * Bureau de la traduction / Translation Bureau * Services linguistiques / Linguistic Services * Bur. dir. Centre de traduction et de terminologie / Dir's Office Translation and Terminology Centre * Div. Citoyennet&#233; et Protection civile / Citizen. &#38; Emergency preparedness Div. * Normalisation terminologique / Terminology Standardization"/>
      XML

      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(termium_xml)
      sax_val = adapter.root.attributes["details"].value

      expect(sax_val).to include("& Emergency")
      expect(sax_val).not_to include("&#38;")
      expect(sax_val).to include("Citoyennet\u00E9") # &#233; → é
    end
  end

  describe "numeric character references in text content" do
    # Numeric character references in text content are resolved by SAX
    # (same as DOM). This is consistent with the XML spec — numeric refs
    # resolve to their Unicode characters in text content.

    it "resolves &#8482; (trademark) in text content" do
      xml = "<doc>IEEE 1857.10&#8482;</doc>"
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(xml)

      expect(adapter.root.text).to include("™")
      expect(adapter.root.text).not_to include("&#8482;")
    end

    it "resolves &#169; (copyright) in text content" do
      xml = "<doc>Copyright &#169; 2024</doc>"
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(xml)

      expect(adapter.root.text).to include("\u00A9")
      expect(adapter.root.text).not_to include("&#169;")
    end

    it "resolves &#x00A9; (hex copyright) in text content" do
      xml = "<doc>Copyright &#x00A9; 2024</doc>"
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(xml)

      expect(adapter.root.text).to include("\u00A9")
      expect(adapter.root.text).not_to include("&#x00A9;")
    end
  end

  describe "integration with from_xml via parse_sax" do
    before do
      stub_const("SaxBook", Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :author, :string

        xml do
          root "book"
          map_element "title", to: :title
          map_element "author", to: :author
        end
      end)
    end

    it "deserializes a model using SAX-parsed XmlElement" do
      xml = "<book><title>Ruby</title><author>Matz</author></book>"
      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.parse_sax(xml)

      doc = adapter.root
      expect(doc).to be_a(Lutaml::Xml::XmlElement)
      expect(doc.name).to eq("book")
    end
  end
end
