# frozen_string_literal: true

require "spec_helper"

RSpec.shared_examples "a consistent XML builder" do
  describe "#create_and_add_element" do
    it "creates an element with attributes" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root", attributes: { "id" => "1" })
      end

      root = builder.doc.root
      expect(root.name).to eq("root")
      expect(root["id"]).to eq("1")
    end

    it "nests elements via block" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root") do
          xml.create_and_add_element("child")
        end
      end

      root = builder.doc.root
      expect(root.children.length).to eq(1)
      expect(root.children.first.name).to eq("child")
    end
  end

  describe "#add_text" do
    it "adds a text node to an element" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root") do
          xml.text("hello")
        end
      end

      expect(builder.to_xml).to include("hello")
    end
  end

  describe "#add_cdata" do
    it "adds a CDATA section to an element" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root") do
          xml.cdata("some data")
        end
      end

      expect(builder.to_xml).to include("<![CDATA[some data]]>")
    end
  end

  describe "#add_comment" do
    it "appends a comment node to an element" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root") do
          xml.add_comment(xml.current_node, "a comment")
        end
      end

      root = builder.doc.root
      comment = root.children.first

      expect(comment).to be_a(Moxml::Comment)
      expect(comment.content).to eq("a comment")
      expect(builder.to_xml).to include("<!--a comment-->")
    end
  end

  describe "#add_xml_fragment" do
    it "parses and inserts XML fragment" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root") do
          xml.add_xml_fragment(xml.current_node, "<child>text</child>")
        end
      end

      expect(builder.to_xml).to include("<child>text</child>")
    end
  end

  describe "#to_xml" do
    it "serializes the built document" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root", attributes: { "key" => "val" }) do
          xml.text("content")
        end
      end

      xml = builder.to_xml
      expect(xml).to include("<root")
      expect(xml).to include("content")
    end

    it "returns empty string when no root" do
      builder = described_class.build
      expect(builder.to_xml).to eq("")
    end
  end

  describe "method_missing DSL" do
    it "creates elements dynamically" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root") do
          xml.create_and_add_element("item", attributes: { "id" => "1" })
        end
      end

      expect(builder.to_xml).to include("item")
    end
  end

  describe "encoding" do
    it "stores encoding from build options" do
      builder = described_class.build(encoding: "ISO-8859-1")
      expect(builder.encoding).to eq("ISO-8859-1")
    end

    it "defaults encoding to nil" do
      builder = described_class.build
      expect(builder.encoding).to be_nil
    end

    it "encodes output XML with specified encoding" do
      builder = described_class.build(encoding: "ISO-8859-1") do |xml|
        xml.create_and_add_element("root") do
          xml.text("café")
        end
      end

      xml = builder.to_xml
      expect(xml.encoding).to eq(Encoding::ISO_8859_1)
      expect(xml).to include("caf")
    end

    it "keeps UTF-8 when no encoding specified" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root") do
          xml.text("café")
        end
      end

      xml = builder.to_xml
      expect(xml.encoding).to eq(Encoding::UTF_8)
      expect(xml).to include("café")
    end
  end

  describe "namespace handling" do
    it "declares xmlns attributes as namespaces" do
      builder = described_class.build do |xml|
        xml.create_and_add_element("root",
                                   attributes: { "xmlns:ns" => "http://example.com" })
      end

      expect(builder.to_xml).to include("xmlns:ns")
      expect(builder.to_xml).to include("http://example.com")
    end
  end
end

RSpec.describe "XML Builder consistency" do
  describe Lutaml::Xml::Builder::Nokogiri do
    it_behaves_like "a consistent XML builder"
  end

  describe Lutaml::Xml::Builder::Ox do
    it_behaves_like "a consistent XML builder"
  end

  describe Lutaml::Xml::Builder::Oga do
    it_behaves_like "a consistent XML builder"
  end

  describe Lutaml::Xml::Builder::Rexml do
    it_behaves_like "a consistent XML builder"
  end
end
