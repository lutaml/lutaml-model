# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml"

RSpec.describe Lutaml::Xml do
  describe "standalone loading" do
    let(:lib_path) { File.expand_path("../../../lib", __dir__) }

    it "lazy-loads the schema namespace from the XML entry point" do
      # rubocop:disable Style/CommandLiteral
      result = `#{RbConfig.ruby} -I#{lib_path} -e 'require "lutaml/xml"; abort "missing Schema autoload" unless Lutaml::Xml.autoload?(:Schema); abort "missing Xsd autoload" unless Lutaml::Xml::Schema.const_defined?(:Xsd, false); puts :ok' 2>&1`
      # rubocop:enable Style/CommandLiteral

      expect($?.success?).to be(true), result
      expect(result).to include("ok")
    end
  end

  describe "schema autoloads" do
    it "matches native-only schema autoload availability" do
      expect(described_class::Schema.const_defined?(:Xsd, false))
        .to be(!Lutaml::Model::RuntimeCompatibility.opal?)
    end
  end

  describe "schema methods" do
    before do
      allow(Lutaml::Model::RuntimeCompatibility).to receive(:opal?)
        .and_return(true)
    end

    it "raises NotImplementedError for XSD generation under Opal" do
      expect do
        Lutaml::Model::Schema.to_xsd(Object)
      end.to raise_error(
        NotImplementedError,
        "XSD schema generation is not available under Opal.",
      )
    end

    it "raises NotImplementedError for RELAX NG generation under Opal" do
      expect do
        Lutaml::Model::Schema.to_relaxng(Object)
      end.to raise_error(
        NotImplementedError,
        "RELAX NG schema generation requires Nokogiri, " \
        "which is not available under Opal.",
      )
    end

    it "raises NotImplementedError for XML schema compilation under Opal" do
      expect do
        Lutaml::Model::Schema.from_xml("<schema/>")
      end.to raise_error(
        NotImplementedError,
        "XML schema compilation is not available under Opal.",
      )
    end
  end

  describe ".detect_xml_adapter" do
    before do
      # Hide any existing constants first
      hide_const("Nokogiri") if Object.const_defined?(:Nokogiri)
      hide_const("Ox") if Object.const_defined?(:Ox)
      hide_const("Oga") if Object.const_defined?(:Oga)
      hide_const("REXML") if Object.const_defined?(:REXML)

      # Stub require to prevent any actual requires during testing
      allow(Lutaml::Model::Utils).to receive(:require).and_return(true)
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

    context "when Oga is available" do
      before do
        stub_const("Oga", Module.new)
      end

      it "returns :oga" do
        expect(described_class.detect_xml_adapter).to eq(:oga)
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
        stub_const("Oga", Module.new)
      end

      it "prefers Nokogiri" do
        expect(described_class.detect_xml_adapter).to eq(:nokogiri)
      end
    end
  end
end
