# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/xml"

RSpec.describe Lutaml::Model::Xml do
  describe ".detect_xml_adapter" do
    before do
      # Hide any existing constants first
      hide_const("Nokogiri") if Object.const_defined?(:Nokogiri)
      hide_const("Ox") if Object.const_defined?(:Ox)
      hide_const("Opal") if Object.const_defined?(:Opal)
    end

    context "when Nokogiri is available" do
      before do
        stub_const("Nokogiri", Module.new)
      end

      it "returns :nokogiri" do
        expect(described_class.detect_xml_adapter).to eq(:nokogiri)
      end
    end

    context "when Ox is available" do
      before do
        stub_const("Ox", Module.new)
      end

      it "returns :ox" do
        expect(described_class.detect_xml_adapter).to eq(:ox)
      end
    end

    context "when Opal is available" do
      before do
        stub_const("Opal", Module.new)
      end

      it "returns :opal" do
        expect(described_class.detect_xml_adapter).to eq(:opal)
      end
    end

    context "when no adapters are available" do
      it "returns nil" do
        expect(described_class.detect_xml_adapter).to be_nil
      end
    end

    context "when multiple adapters are available" do
      before do
        stub_const("Nokogiri", Module.new)
        stub_const("Ox", Module.new)
        stub_const("Opal", Module.new)
      end

      it "prefers Nokogiri" do
        expect(described_class.detect_xml_adapter).to eq(:nokogiri)
      end
    end
  end
end
