# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Xml::Builder::Oga do
  describe "#add_comment" do
    it "appends a comment node to an element" do
      builder = described_class.build do |xml|
        xml.element("root") do
          xml.add_comment(xml.current_node, "a comment")
        end
      end

      root = builder.document.root
      comment = root.children.first

      expect(comment).to be_a(Moxml::Comment)
      expect(comment.content).to eq("a comment")
      expect(builder.to_xml).to include("<!--a comment-->")
    end

    it "appends a comment node to the current root when given the document" do
      builder = described_class.build do |xml|
        xml.element("root")
        xml.add_comment(xml.document, "a comment")
      end

      root = builder.document.root
      comment = root.children.first

      expect(comment).to be_a(Moxml::Comment)
      expect(comment.content).to eq("a comment")
    end

    it "encodes comment text using the builder encoding" do
      builder = described_class.build(encoding: "ISO-8859-1") do |xml|
        xml.element("root") do
          xml.add_comment(xml.current_node, "café")
        end
      end

      root = builder.document.root
      comment = root.children.first

      expect(comment.content.encoding).to eq(Encoding::ISO_8859_1)
      expect(comment.content).to eq("café".encode("ISO-8859-1"))
    end
  end
end
