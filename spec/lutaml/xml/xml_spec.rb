# frozen_string_literal: true

require "spec_helper"
require "open3"
require "lutaml/xml"

RSpec.describe Lutaml::Xml do
  let(:lib_path) { File.expand_path("../../../lib", __dir__) }

  def run_ruby(script)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I#{lib_path}", "-e", script
    )

    [stdout + stderr, status]
  end

  describe "standalone loading" do
    it "lazy-loads the schema namespace from the XML entry point" do
      script = <<~RUBY
        require "lutaml/xml"
        abort "missing Schema autoload" unless Lutaml::Xml.autoload?(:Schema)
        unless Lutaml::Xml::Schema.const_defined?(:Xsd, false)
          abort "missing Xsd autoload"
        end
        puts :ok
      RUBY

      result, status = run_ruby(script)

      expect(status.success?).to be(true), result
      expect(result).to include("ok")
    end
  end

  describe "schema autoloads" do
    it "matches native-only schema autoload availability" do
      expect(described_class::Schema.const_defined?(:Xsd, false))
        .to be(!Lutaml::Model::RuntimeCompatibility.opal?)
    end

    it "does not autoload schema constants when loaded under Opal" do
      script = <<~'RUBY'
        require "lutaml/model/runtime_compatibility"

        module Lutaml
          module Model
            module RuntimeCompatibility
              def self.opal?
                true
              end
            end
          end
        end

        require "lutaml/xml/schema"

        schema_constants = %i[
          Xsd XsdSchema RelaxngSchema Builder BuiltinTypes
        ]

        loaded_constants = schema_constants.select do |constant_name|
          Lutaml::Xml::Schema.autoload?(constant_name) ||
            Lutaml::Xml::Schema.const_defined?(constant_name, false)
        end

        if loaded_constants.any?
          abort "loaded schema constants: #{loaded_constants.join(', ')}"
        end

        puts :ok
      RUBY

      result, status = run_ruby(script)

      expect(status.success?).to be(true), result
      expect(result).to include("ok")
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
    # #1224: detection answers the LANE, not an engine. The
    # engine-preference chain (leptris-when-present, Nokogiri, Oga,
    # Ox fallbacks) lives inside Moxml::Config.runtime_default_adapter
    # and is verified by moxml's own suite; the facade resolves it at
    # every parse, so lutaml-model has no engine preference of its own.
    it "always answers the moxml lane regardless of loaded engines" do
      stub_const("Nokogiri", Module.new)
      stub_const("Ox", Module.new)
      stub_const("Oga", Module.new)

      expect(described_class.detect_xml_adapter).to eq(:moxml)
    end

    it "answers the moxml lane when no engine is loadable" do
      hide_const("Nokogiri") if Object.const_defined?(:Nokogiri)
      hide_const("Ox") if Object.const_defined?(:Ox)
      hide_const("Oga") if Object.const_defined?(:Oga)

      expect(described_class.detect_xml_adapter).to eq(:moxml)
    end
  end
end
