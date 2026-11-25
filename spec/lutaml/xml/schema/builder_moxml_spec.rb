# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Xml::Schema::Builder do
  # issue #1184: schema generation rides the CONFIGURED engine through
  # the moxml layer. The dedicated Nokogiri/Oga wrappers keep their
  # lanes; every other engine (ox, leptris, rexml) generates through
  # the Moxml wrapper instead of silently substituting Nokogiri.

  describe "engine-following selection" do
    it "keeps the dedicated Nokogiri wrapper when Nokogiri is requested" do
      builder = described_class.new(adapter_type: :nokogiri)

      expect(builder.adapter_type).to eq(:nokogiri)
      expect(builder.builder).to be_a(described_class::Nokogiri)
    end

    it "routes other configured engines through the Moxml wrapper" do
      builder = described_class.new(adapter_type: :ox)

      expect(builder.adapter_type).to eq(:ox)
      expect(builder.builder).to be_a(described_class::Moxml)
    end
  end

  describe "Moxml wrapper emission" do
    let(:builder) do
      described_class.new(adapter_type: :ox) do |xml|
        xml.schema(targetNamespace: "http://example.com") do
          xml.element(name: "name", type: "xs:string")
        end
      end
    end

    it "emits the XML declaration with the encoding" do
      expect(builder.to_xml).to start_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    end

    it "emits the nested schema DSL shape" do
      xml = builder.to_xml

      expect(xml).to include("<schema")
      expect(xml).to include("targetNamespace=\"http://example.com\"")
      # the empty-element form is lane-serialized; both forms are
      # model-legal XML — the DSL shape is what parity binds here
      expect(xml).to match(/<element name="name" type="xs:string"\s*\/?>(<\/element>)?/)
    end

    it "honors the pretty option" do
      expect(builder.to_xml(pretty: true)).to include("\n")
    end
  end
end
