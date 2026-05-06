# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::Transform do
  let(:transform) { described_class.new(nil) }

  describe "#resolve_subject_uri" do
    it "returns nil when mapping has no subject" do
      mapping = Lutaml::Rdf::Mapping.new
      expect(transform.send(:resolve_subject_uri, mapping, double)).to be_nil
    end

    it "calls subject proc with instance" do
      mapping = Lutaml::Rdf::Mapping.new
      mapping.subject { |i| "http://example.org/#{i}" }

      result = transform.send(:resolve_subject_uri, mapping, "test")
      expect(result).to eq("http://example.org/test")
    end
  end

  describe "#resolve_type_uri" do
    it "returns nil when mapping has no type" do
      mapping = Lutaml::Rdf::Mapping.new
      expect(transform.send(:resolve_type_uri, mapping)).to be_nil
    end

    it "resolves compact IRI to full URI" do
      mapping = Lutaml::Rdf::Mapping.new
      stub_const("TestNs", Class.new(Lutaml::Rdf::Namespace) do
        uri "http://example.org/"
        prefix "ex"
      end)
      mapping.namespace(TestNs)
      mapping.type "ex:Thing"

      result = transform.send(:resolve_type_uri, mapping)
      expect(result).to eq("http://example.org/Thing")
    end
  end

  describe "#resolve_type_compact" do
    it "returns the compact form" do
      mapping = Lutaml::Rdf::Mapping.new
      mapping.type "skos:Concept"

      expect(transform.send(:resolve_type_compact,
                            mapping)).to eq("skos:Concept")
    end
  end

  describe "#extract_language" do
    it "extracts language from LanguageTagged objects" do
      literal = Lutaml::Rdf::Literal.new("hello", language: "eng")
      expect(transform.send(:extract_language, literal)).to eq("eng")
    end

    it "returns nil for plain strings" do
      expect(transform.send(:extract_language, "hello")).to be_nil
    end

    it "returns nil for non-LanguageTagged objects" do
      expect(transform.send(:extract_language, 42)).to be_nil
    end
  end

  describe "#build_instance" do
    it "constructs a model instance with resolved register" do
      stub_const("BuildTestModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end)

      context = BuildTestModel
      t = described_class.new(context)
      instance = t.send(:build_instance, { name: "test" }, {})
      expect(instance).to be_a(BuildTestModel)
      expect(instance.name).to eq("test")
    end
  end
end
