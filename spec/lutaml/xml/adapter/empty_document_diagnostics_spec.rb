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
#
# moxml#369 changed the recoverable-malformation contract: the leptris
# adapter's non-strict parse now RECOVERS (the engine's recover mode,
# leptris#1660) and returns the best-effort tree instead of failing —
# a mismatched closer yields a document, not a raise. Only inputs with
# nothing to recover into (whitespace-only) still reach the guard,
# carrying the recovery diagnostic.
RSpec.describe "empty-document errors surface engine parse diagnostics" do
  describe Lutaml::Xml::Adapter::LeptrisAdapter do
    it "returns a recovered tree for recoverable malformations (moxml#369)" do
      recovered = Gem::Version.new(Gem.loaded_specs.fetch("moxml").version) >=
                  Gem::Version.new("0.5.131")
      unless recovered
        skip "moxml predates the recover-mode wiring (0.5.131)"
      end

      doc = described_class.parse("<root><a>x</b></root>")
      expect(doc.root.name).to eq("root")
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
