# frozen_string_literal: true

require "spec_helper"
require "oga"

RSpec.describe Lutaml::Xml::Builder::Oga do
  describe "#add_comment" do
    it "appends a comment node to an element" do
      builder = described_class.build do |xml|
        xml.element("root") do
          xml.add_comment(xml.current_node, "a comment")
        end
      end

      root = builder.document.children.first
      comment = root.children.first

      expect(comment).to be_a(Oga::XML::Comment)
      expect(comment.text).to eq("a comment")
      expect(builder.document.to_xml).to include("<!--a comment-->")
    end

    it "appends a comment node to the current root when given the document" do
      builder = described_class.build do |xml|
        xml.element("root")
        xml.add_comment(xml.document, "a comment")
      end

      root = builder.document.children.first
      comment = root.children.first

      expect(comment).to be_a(Oga::XML::Comment)
      expect(comment.text).to eq("a comment")
    end
  end
end
