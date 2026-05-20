# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::Transform do
  describe "#resolve_subject_uri" do
    it "returns nil when mapping has no subject" do
      mapping = Lutaml::Rdf::Mapping.new
      transform = described_class.new(nil)
      expect(transform.resolve_subject_uri(mapping, double)).to be_nil
    end

    it "calls subject proc with instance" do
      mapping = Lutaml::Rdf::Mapping.new
      mapping.subject { |i| "http://example.org/#{i}" }

      transform = described_class.new(nil)
      result = transform.resolve_subject_uri(mapping, "test")
      expect(result).to eq("http://example.org/test")
    end
  end

  describe "#resolve_single_type_uri" do
    it "resolves compact IRI to full URI" do
      stub_const("TestNs", Class.new(Lutaml::Rdf::Namespace) do
        uri "http://example.org/"
        prefix "ex"
      end)
      mapping = Lutaml::Rdf::Mapping.new
      mapping.namespace(TestNs)
      mapping.type "ex:Thing"

      transform = described_class.new(nil)
      result = transform.resolve_single_type_uri(mapping, "ex:Thing")
      expect(result).to eq("http://example.org/Thing")
    end
  end

  describe "#resolve_type_uris" do
    it "returns empty array when mapping has no types" do
      mapping = Lutaml::Rdf::Mapping.new
      transform = described_class.new(nil)
      expect(transform.resolve_type_uris(mapping)).to eq([])
    end

    it "resolves all type compact IRIs to full URIs" do
      stub_const("MultiNs", Class.new(Lutaml::Rdf::Namespace) do
        uri "http://example.org/"
        prefix "ex"
      end)
      mapping = Lutaml::Rdf::Mapping.new
      mapping.namespace(MultiNs)
      mapping.type ["ex:Thing", "ex:Other"]

      transform = described_class.new(nil)
      result = transform.resolve_type_uris(mapping)
      expect(result).to eq(["http://example.org/Thing", "http://example.org/Other"])
    end
  end

  describe "#extract_language" do
    it "extracts language from LanguageTagged objects" do
      literal = Lutaml::Rdf::Literal.new("hello", language: "eng")
      transform = described_class.new(nil)
      expect(transform.extract_language(literal)).to eq("eng")
    end

    it "returns nil for plain strings" do
      transform = described_class.new(nil)
      expect(transform.extract_language("hello")).to be_nil
    end

    it "returns nil for non-LanguageTagged objects" do
      transform = described_class.new(nil)
      expect(transform.extract_language(42)).to be_nil
    end
  end

  describe "#each_member" do
    it "iterates over collection attribute values" do
      stub_const("MemberItem", Class.new do
        attr_reader :label

        def initialize(label)
          @label = label
        end
      end)
      stub_const("MemberParent", Class.new(Lutaml::Model::Serializable) do
        attribute :items, :string, collection: true
      end)

      instance = MemberParent.new(items: ["a", "b"])
      member_rule = Lutaml::Rdf::MemberRule.new(:items)
      transform = described_class.new(nil)

      collected = []
      transform.each_member(instance, member_rule) { |m| collected << m }
      expect(collected).to eq(["a", "b"])
    end

    it "handles nil collection as empty" do
      stub_const("NilParent", Class.new(Lutaml::Model::Serializable) do
        attribute :items, :string, collection: true
      end)

      instance = NilParent.new
      member_rule = Lutaml::Rdf::MemberRule.new(:items)
      transform = described_class.new(nil)

      collected = []
      transform.each_member(instance, member_rule) { |m| collected << m }
      expect(collected).to eq([])
    end
  end

  describe "#member_mapping_for" do
    it "returns the mapping for the given format" do
      stub_const("MappedChild", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace
          subject { |m| "http://example.org/#{m.label}" } # rubocop:disable RSpec/NamedSubject

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :label
        end
      end)

      member = MappedChild.new(label: "test")
      transform = described_class.new(nil)
      mapping = transform.member_mapping_for(member, :turtle)
      expect(mapping).to be_a(Lutaml::Rdf::Mapping)
    end

    it "returns nil when no mapping for format" do
      stub_const("UnmappedChild", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
      end)

      member = UnmappedChild.new(label: "test")
      transform = described_class.new(nil)
      expect(transform.member_mapping_for(member, :turtle)).to be_nil
    end
  end
end
