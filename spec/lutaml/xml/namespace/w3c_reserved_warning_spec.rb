# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Xml::Namespace do
  describe "W3C reserved namespace warning" do
    around do |example|
      # Suppress warnings during test to avoid noise
      original_stderr = $stderr
      $stderr = StringIO.new
      example.run
      $stderr = original_stderr
    end

    describe "when defining namespace with W3C-reserved URI" do
      it "warns when defining namespace with xml: URI" do
        # Capture warnings
        warnings = []
        allow(Lutaml::Model::Logger).to receive(:warn) do |msg, _path|
          warnings << msg
        end

        klass = Class.new(Lutaml::Xml::Namespace) do
          uri "http://www.w3.org/XML/1998/namespace"
        end

        expect {
          klass.new  # Instantiate to trigger warning
        }.not_to raise_error

        expect(warnings.join).to include("W3C-reserved URI")
        expect(warnings.join).to include("xml: attributes")
      end
    end

    describe "when defining namespace with W3C-reserved prefix" do
      it "warns when defining namespace with xsi prefix" do
        warnings = []
        allow(Lutaml::Model::Logger).to receive(:warn) do |msg, _path|
          warnings << msg
        end

        klass = Class.new(Lutaml::Xml::Namespace) do
          uri "http://example.com/ns"
          prefix_default "xsi"
        end

        expect {
          klass.new  # Instantiate to trigger warning
        }.not_to raise_error

        expect(warnings.join).to include("W3C-reserved prefix")
        expect(warnings.join).to include("xsi")
      end

      it "warns when defining namespace with xml prefix" do
        warnings = []
        allow(Lutaml::Model::Logger).to receive(:warn) do |msg, _path|
          warnings << msg
        end

        klass = Class.new(Lutaml::Xml::Namespace) do
          uri "http://example.com/ns"
          prefix_default "xml"
        end

        expect {
          klass.new  # Instantiate to trigger warning
        }.not_to raise_error

        expect(warnings.join).to include("W3C-reserved prefix")
        expect(warnings.join).to include("RESERVED")
      end

      it "warns when defining namespace with xlink prefix" do
        warnings = []
        allow(Lutaml::Model::Logger).to receive(:warn) do |msg, _path|
          warnings << msg
        end

        klass = Class.new(Lutaml::Xml::Namespace) do
          uri "http://example.com/ns"
          prefix_default "xlink"
        end

        expect {
          klass.new  # Instantiate to trigger warning
        }.not_to raise_error

        expect(warnings.join).to include("W3C-reserved prefix")
        expect(warnings.join).to include("xlink")
      end

      it "warns when defining namespace with xs prefix" do
        warnings = []
        allow(Lutaml::Model::Logger).to receive(:warn) do |msg, _path|
          warnings << msg
        end

        klass = Class.new(Lutaml::Xml::Namespace) do
          uri "http://example.com/ns"
          prefix_default "xs"
        end

        expect {
          klass.new  # Instantiate to trigger warning
        }.not_to raise_error

        expect(warnings.join).to include("W3C-reserved prefix")
        expect(warnings.join).to include("xs")
      end
    end

    describe "when defining namespace with non-reserved values" do
      it "does not warn for non-reserved namespaces" do
        warnings = []
        allow(Lutaml::Model::Logger).to receive(:warn) do |msg, _path|
          warnings << msg
        end

        klass = Class.new(Lutaml::Xml::Namespace) do
          uri "http://example.com/my-namespace"
          prefix_default "my"
        end

        expect {
          klass.new  # Instantiate to trigger potential warning
        }.not_to raise_error

        expect(warnings).to be_empty
      end
    end
  end
end

RSpec.describe "Built-in W3C namespaces" do
  it "do not trigger W3C reserved warnings" do
    warnings = []
    allow(Lutaml::Model::Logger).to receive(:warn) do |msg, _path|
      warnings << msg
    end

    # These should not warn despite being W3C-reserved
    expect { Lutaml::Xml::W3c::XmlNamespace.new }.not_to raise_error
    expect { Lutaml::Xml::W3c::XsiNamespace.new }.not_to raise_error
    expect { Lutaml::Xml::W3c::XlinkNamespace.new }.not_to raise_error
    expect { Lutaml::Xml::W3c::XsNamespace.new }.not_to raise_error

    # No warnings should have been issued for built-in namespaces
    expect(warnings).to be_empty
  end
end
