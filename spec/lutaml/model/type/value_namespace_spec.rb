require "spec_helper"
require "lutaml/model"

RSpec.describe Lutaml::Model::Type::Value, "xml_namespace directive" do
  # Define test namespace classes
  let(:test_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "https://example.com/test"
      prefix_default "test"
    end
  end

  let(:other_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "https://example.com/other"
      prefix_default "other"
    end
  end

  describe ".xml_namespace" do
    it "sets and gets namespace class" do
      type_class = Class.new(described_class)
      type_class.xml_namespace(test_namespace)

      expect(type_class.xml_namespace).to eq(test_namespace)
    end

    it "returns nil when no namespace is set" do
      type_class = Class.new(described_class)

      expect(type_class.xml_namespace).to be_nil
    end

    it "raises error for non-XmlNamespace class" do
      type_class = Class.new(described_class)

      expect do
        type_class.xml_namespace(String)
      end.to raise_error(ArgumentError, /XmlNamespace/)
    end

    it "allows changing namespace" do
      type_class = Class.new(described_class)
      type_class.xml_namespace(test_namespace)
      type_class.xml_namespace(other_namespace)

      expect(type_class.xml_namespace).to eq(other_namespace)
    end
  end

  describe ".namespace_uri" do
    it "returns URI from namespace class" do
      type_class = Class.new(described_class)
      type_class.xml_namespace(test_namespace)

      expect(type_class.namespace_uri).to eq("https://example.com/test")
    end

    it "returns nil when no namespace is set" do
      type_class = Class.new(described_class)

      expect(type_class.namespace_uri).to be_nil
    end
  end

  describe ".namespace_prefix" do
    it "returns prefix from namespace class" do
      type_class = Class.new(described_class)
      type_class.xml_namespace(test_namespace)

      expect(type_class.namespace_prefix).to eq("test")
    end

    it "returns nil when no namespace is set" do
      type_class = Class.new(described_class)

      expect(type_class.namespace_prefix).to be_nil
    end
  end

  describe ".xsd_type" do
    it "sets and gets custom xsd_type" do
      type_class = Class.new(described_class)
      type_class.xsd_type("custom:Type")

      expect(type_class.xsd_type).to eq("custom:Type")
    end

    it "returns default_xsd_type when not set" do
      type_class = Class.new(described_class) do
        def self.default_xsd_type
          "xs:string"
        end
      end

      expect(type_class.xsd_type).to eq("xs:string")
    end

    it "allows changing xsd_type" do
      type_class = Class.new(described_class)
      type_class.xsd_type("first:Type")
      type_class.xsd_type("second:Type")

      expect(type_class.xsd_type).to eq("second:Type")
    end
  end

  describe ".default_xsd_type" do
    it "returns xs:anyType by default" do
      type_class = Class.new(described_class)

      expect(type_class.default_xsd_type).to eq("xs:anyType")
    end

    it "can be overridden in subclasses" do
      type_class = Class.new(described_class) do
        def self.default_xsd_type
          "xs:customType"
        end
      end

      expect(type_class.default_xsd_type).to eq("xs:customType")
    end
  end

  describe "combined xml_namespace and xsd_type" do
    it "can set both xml_namespace and xsd_type" do
      type_class = Class.new(described_class)
      type_class.xml_namespace(test_namespace)
      type_class.xsd_type("CustomType")

      expect(type_class.xml_namespace).to eq(test_namespace)
      expect(type_class.namespace_uri).to eq("https://example.com/test")
      expect(type_class.namespace_prefix).to eq("test")
      expect(type_class.xsd_type).to eq("CustomType")
    end
  end

  describe "backward compatibility with xml block" do
    it "shows deprecation warning when using xml block" do
      ns_class = test_namespace
      type_class = Class.new(described_class)

      expect do
        type_class.xml do
          namespace ns_class
        end
      end.to output(/DEPRECATION.*xml block.*deprecated/).to_stderr
    end

    it "syncs namespace from xml block to new directive" do
      ns_class = test_namespace
      type_class = Class.new(described_class)

      # Suppress deprecation warning for test
      allow($stderr).to receive(:write)

      type_class.xml do
        namespace ns_class
      end

      expect(type_class.xml_namespace).to eq(ns_class)
    end
  end

  describe "backward compatibility with .namespace" do
    it "shows deprecation warning when using .namespace" do
      type_class = Class.new(described_class)

      expect do
        type_class.namespace(test_namespace)
      end.to output(/DEPRECATION.*xml_namespace/).to_stderr
    end

    it "delegates to xml_namespace" do
      type_class = Class.new(described_class)

      # Suppress deprecation warning for test
      allow($stderr).to receive(:write)

      type_class.namespace(test_namespace)

      expect(type_class.xml_namespace).to eq(test_namespace)
      expect(type_class.namespace_uri).to eq("https://example.com/test")
    end
  end
end
