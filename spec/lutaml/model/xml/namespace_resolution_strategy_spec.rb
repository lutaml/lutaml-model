# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::Xml::NamespaceResolutionStrategy do
  describe ".resolve" do
    it "returns namespace info hash" do
      strategy = described_class.new(
        use_prefix: true,
        prefix: "test",
        namespace_uri: "http://example.com"
      )

      result = strategy.resolve

      expect(result).to eq(
        use_prefix: true,
        prefix: "test",
        uri: "http://example.com",
        requires_blank_xmlns: false
      )
    end
  end
end

RSpec.describe Lutaml::Model::Xml::BlankNamespaceStrategy do
  describe "#resolve" do
    it "resolves to blank namespace" do
      strategy = described_class.new
      result = strategy.resolve

      expect(result[:use_prefix]).to be false
      expect(result[:prefix]).to be_nil
      expect(result[:uri]).to be_nil
    end
  end

  describe "use case: native type without xml_namespace" do
    it "ensures native types serialize in blank namespace" do
      strategy = described_class.new

      result = strategy.resolve

      # Native types should have no namespace markers
      expect(result[:use_prefix]).to be false
      expect(result[:prefix]).to be_nil
      expect(result[:uri]).to be_nil
    end
  end
end

RSpec.describe Lutaml::Model::Xml::InheritedNamespaceStrategy do
  let(:test_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      def self.uri
        "http://example.com/test"
      end

      def self.prefix_default
        "test"
      end

      def self.to_key
        "test"
      end
    end
  end

  describe "#resolve with default format" do
    it "inherits default namespace from parent" do
      parent_decl = Lutaml::Model::Xml::NamespaceDeclaration.new(
        ns_object: test_namespace,
        format: :default,
        xmlns_declaration: 'xmlns="http://example.com/test"',
        declared_at: :here
      )

      strategy = described_class.new(parent_decl)
      result = strategy.resolve

      expect(result[:use_prefix]).to be false
      expect(result[:prefix]).to eq("test")
      expect(result[:uri]).to eq("http://example.com/test")
    end
  end

  describe "#resolve with prefix format" do
    it "inherits prefixed namespace from parent" do
      parent_decl = Lutaml::Model::Xml::NamespaceDeclaration.new(
        ns_object: test_namespace,
        format: :prefix,
        xmlns_declaration: 'xmlns:test="http://example.com/test"',
        declared_at: :here
      )

      strategy = described_class.new(parent_decl)
      result = strategy.resolve

      expect(result[:use_prefix]).to be true
      expect(result[:prefix]).to eq("test")
      expect(result[:uri]).to eq("http://example.com/test")
    end
  end
end

RSpec.describe Lutaml::Model::Xml::TypeNamespaceStrategy do
  let(:type_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      def self.uri
        "http://example.com/custom"
      end

      def self.prefix_default
        "custom"
      end

      def self.to_key
        "custom"
      end
    end
  end

  let(:custom_type) do
    ns = type_namespace
    Class.new(Lutaml::Model::Type::String) do
      define_singleton_method(:xml_namespace) { ns }
    end
  end

  describe "#resolve with default format" do
    it "uses type's namespace in default format" do
      type_ns_decl = Lutaml::Model::Xml::NamespaceDeclaration.new(
        ns_object: type_namespace,
        format: :default,
        xmlns_declaration: 'xmlns="http://example.com/custom"',
        declared_at: :local_on_use
      )

      strategy = described_class.new(type_ns_decl, custom_type)
      result = strategy.resolve

      expect(result[:use_prefix]).to be false
      expect(result[:prefix]).to eq("custom")
      expect(result[:uri]).to eq("http://example.com/custom")
    end
  end

  describe "#resolve with prefix format" do
    it "uses type's namespace with prefix" do
      type_ns_decl = Lutaml::Model::Xml::NamespaceDeclaration.new(
        ns_object: type_namespace,
        format: :prefix,
        xmlns_declaration: 'xmlns:custom="http://example.com/custom"',
        declared_at: :local_on_use
      )

      strategy = described_class.new(type_ns_decl, custom_type)
      result = strategy.resolve

      expect(result[:use_prefix]).to be true
      expect(result[:prefix]).to eq("custom")
      expect(result[:uri]).to eq("http://example.com/custom")
    end
  end
end

RSpec.describe Lutaml::Model::Xml::ExplicitNamespaceStrategy do
  let(:test_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      def self.uri
        "http://example.com/explicit"
      end

      def self.prefix_default
        "ex"
      end

      def self.to_key
        "explicit"
      end
    end
  end

  let(:ns_decl) do
    Lutaml::Model::Xml::NamespaceDeclaration.new(
      ns_object: test_namespace,
      format: :prefix,
      xmlns_declaration: 'xmlns:ex="http://example.com/explicit"',
      declared_at: :here
    )
  end

  describe "#resolve with unqualified element" do
    it "forces blank namespace even with prefix declaration" do
      rule = double(
        "MappingRule",
        unqualified?: true,
        qualified?: false,
        prefix_set?: false
      )

      strategy = described_class.new(ns_decl, rule)
      result = strategy.resolve

      expect(result[:use_prefix]).to be false
      expect(result[:prefix]).to be_nil
      expect(result[:uri]).to eq("http://example.com/explicit")
    end
  end

  describe "#resolve with qualified element" do
    it "forces prefix format" do
      rule = double(
        "MappingRule",
        unqualified?: false,
        qualified?: true,
        prefix_set?: false
      )

      strategy = described_class.new(ns_decl, rule)
      result = strategy.resolve

      expect(result[:use_prefix]).to be true
      expect(result[:prefix]).to eq("ex")
      expect(result[:uri]).to eq("http://example.com/explicit")
    end
  end

  describe "#resolve with prefix_set element" do
    it "forces prefix format" do
      rule = double(
        "MappingRule",
        unqualified?: false,
        qualified?: false,
        prefix_set?: true
      )

      strategy = described_class.new(ns_decl, rule)
      result = strategy.resolve

      expect(result[:use_prefix]).to be true
      expect(result[:prefix]).to eq("ex")
      expect(result[:uri]).to eq("http://example.com/explicit")
    end
  end

  describe "#resolve with default namespace declaration" do
    let(:default_ns_decl) do
      Lutaml::Model::Xml::NamespaceDeclaration.new(
        ns_object: test_namespace,
        format: :default,
        xmlns_declaration: 'xmlns="http://example.com/explicit"',
        declared_at: :here
      )
    end

    it "follows declaration format when no explicit directive" do
      rule = double(
        "MappingRule",
        unqualified?: false,
        qualified?: false,
        prefix_set?: false
      )

      strategy = described_class.new(default_ns_decl, rule)
      result = strategy.resolve

      expect(result[:use_prefix]).to be false
      expect(result[:prefix]).to be_nil
      expect(result[:uri]).to eq("http://example.com/explicit")
    end
  end
end