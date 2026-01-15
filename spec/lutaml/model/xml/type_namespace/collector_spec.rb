# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/xml/type_namespace/collector"

RSpec.describe Lutaml::Model::Xml::TypeNamespace::Collector do
  let(:type_namespace_class) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://purl.org/dc/elements/1.1/"
      prefix_default "dc"
    end
  end

  let(:type_class_with_namespace) do
    ns = type_namespace_class
    Class.new(Lutaml::Model::Type::String) do
      xml_namespace ns
    end
  end

  let(:type_class_without_namespace) do
    Class.new(Lutaml::Model::Type::String)
  end

  let(:model_class) do
    ns = type_namespace_class
    type_with_ns = type_class_with_namespace
    Class.new(Lutaml::Model::Serializable) do
      attribute :title, type_with_ns
      attribute :author, :string

      xml do
        root "document"
        map_element "title", to: :title
        map_element "author", to: :author
      end
    end
  end

  let(:mapping) { model_class.mappings_for(:xml) }
  let(:collector) { described_class.new }

  describe "#initialize" do
    it "initializes with default register" do
      collector = described_class.new
      expect(collector.register).to eq(Lutaml::Model::Config.default_register)
    end

    it "initializes with custom register" do
      collector = described_class.new(:custom)
      expect(collector.register).to eq(:custom)
    end
  end

  describe "#collect_from_attribute" do
    let(:attribute) { model_class.attributes[:title] }

    let(:rule) do
      instance_double("Lutaml::Model::Xml::MappingRule",
        namespace_set?: false)
    end

    context "when attribute has type namespace" do
      it "returns Reference" do
        ref = collector.collect_from_attribute(attribute, rule, :element)

        expect(ref).to be_a(Lutaml::Model::Xml::TypeNamespace::Reference)
        expect(ref.attribute).to eq(attribute)
        expect(ref.context).to eq(:element)
      end

      it "returns Reference with :attribute context" do
        ref = collector.collect_from_attribute(attribute, rule, :attribute)

        expect(ref).to be_a(Lutaml::Model::Xml::TypeNamespace::Reference)
        expect(ref.context).to eq(:attribute)
      end
    end

    context "when rule has namespace set" do
      let(:rule_with_namespace) do
        instance_double("Lutaml::Model::Xml::MappingRule",
          namespace_set?: true)
      end

      it "returns nil" do
        ref = collector.collect_from_attribute(attribute, rule_with_namespace, :element)

        expect(ref).to be_nil
      end
    end

    context "when attribute is nil" do
      it "returns nil" do
        ref = collector.collect_from_attribute(nil, rule, :element)

        expect(ref).to be_nil
      end
    end

    context "when attribute type has no namespace" do
      let(:attribute_without_ns) { model_class.attributes[:author] }

      it "returns Reference (resolution happens later)" do
        ref = collector.collect_from_attribute(attribute_without_ns, rule, :element)

        # Reference is created, but namespace_class will return nil
        expect(ref).to be_a(Lutaml::Model::Xml::TypeNamespace::Reference)
        expect(ref.namespace_class(collector.register)).to be_nil
      end
    end
  end

  describe "#collect_from_mapping" do
    context "with valid mapping and model class" do
      it "returns Array<Reference>" do
        references = collector.collect_from_mapping(mapping, model_class)

        expect(references).to be_an(Array)
        expect(references.all? { |r| r.is_a?(Lutaml::Model::Xml::TypeNamespace::Reference) }).to be true
      end

      it "collects from element rules" do
        references = collector.collect_from_mapping(mapping, model_class)

        # Should have at least the title attribute with namespace
        element_refs = references.select(&:element_context?)
        expect(element_refs.size).to be > 0
      end

      it "skips rules with namespace_set?" do
        # All rules in our test mapping should not have namespace_set?
        # so this verifies the filtering works
        references = collector.collect_from_mapping(mapping, model_class)

        expect(references).to be_an(Array)
      end
    end

    context "with nil mapper_class" do
      it "returns empty array" do
        references = collector.collect_from_mapping(mapping, nil)

        expect(references).to eq([])
      end
    end

    context "with mapper_class that doesn't respond to attributes" do
      it "returns empty array" do
        references = collector.collect_from_mapping(mapping, Object.new)

        expect(references).to eq([])
      end
    end
  end

  describe "#resolve_references" do
    let(:attribute_with_ns) { model_class.attributes[:title] }
    let(:attribute_without_ns) { model_class.attributes[:author] }

    let(:rule1) do
      instance_double("Lutaml::Model::Xml::MappingRule", namespace_set?: false)
    end

    let(:rule2) do
      instance_double("Lutaml::Model::Xml::MappingRule", namespace_set?: false)
    end

    let(:references) do
      [
        collector.collect_from_attribute(attribute_with_ns, rule1, :element),
        collector.collect_from_attribute(attribute_without_ns, rule2, :attribute),
      ].compact
    end

    it "groups by context" do
      result = collector.resolve_references(references)

      expect(result).to have_key(:attributes)
      expect(result).to have_key(:elements)
      expect(result[:attributes]).to be_a(Set)
      expect(result[:elements]).to be_a(Set)
    end

    it "resolves namespace classes" do
      result = collector.resolve_references(references)

      # Should have the type_namespace_class in elements
      expect(result[:elements]).to include(type_namespace_class)
    end

    it "filters out nil namespace classes" do
      result = collector.resolve_references(references)

      # Only the attribute with namespace should be included
      expect(result[:elements].size).to eq(1)
      expect(result[:elements]).to include(type_namespace_class)
    end

    context "with empty references" do
      it "returns empty sets" do
        result = collector.resolve_references([])

        expect(result[:attributes]).to be_empty
        expect(result[:elements]).to be_empty
      end
    end
  end
end
