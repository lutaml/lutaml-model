# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml/adapter/leptris_adapter"
require "lutaml/xml/adapter/nokogiri_adapter"

# A failed parse reaches the empty-document guard as a document with no
# root, indistinguishable from genuinely empty input. The engine's parse
# diagnostics ride the document (moxml attachments :parse_errors) and
# must surface in the raised message — otherwise the error names the
# input's emptiness while the input is neither empty nor the problem
# (lutaml-model#956).
RSpec.describe "empty-document errors surface engine parse diagnostics" do
  describe Lutaml::Xml::Adapter::LeptrisAdapter do
    it "appends the engine diagnostic when the parse failed" do
      expect do
        described_class.parse("<root><a>x</b></root>")
      end.to raise_error(Lutaml::Model::InvalidFormatError) do |error|
        expect(error.message).to include("the XML engine reported:")
        expect(error.message).to include("XML parse error at byte 14")
      end
    end

    it "reports the engine diagnostic for whitespace-only input" do
      expect do
        described_class.parse("   ")
      end.to raise_error(Lutaml::Model::InvalidFormatError, /the XML engine reported:/)
    end
  end

  describe Lutaml::Xml::Adapter::NokogiriAdapter do
    it "keeps the plain empty-document message when the engine reported nothing" do
      expect do
        described_class.parse("")
      end.to raise_error(Lutaml::Model::InvalidFormatError) do |error|
        expect(error.message).to include("The XML may be empty")
        expect(error.message).not_to include("the XML engine reported:")
      end
    end
  end
end
