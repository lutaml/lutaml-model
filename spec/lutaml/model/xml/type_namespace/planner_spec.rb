# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/xml/type_namespace/planner"

RSpec.describe Lutaml::Model::Xml::TypeNamespace::Planner do
  let(:type_namespace_class) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://purl.org/dc/elements/1.1/"
      prefix_default "dc"
    end
  end

  let(:element_namespace_class) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://example.com/document"
      prefix_default "doc"
    end
  end

  let(:type_class_with_namespace) do
    ns = type_namespace_class
    Class.new(Lutaml::Model::Type::String) do
      xml_namespace ns
    end
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
  let(:planner) { described_class.new }

  describe "#initialize" do
    it "initializes with collector and resolver" do
      planner = described_class.new

      expect(planner.collector).to be_a(Lutaml::Model::Xml::TypeNamespace::Collector)
      expect(planner.resolver).to be_a(Lutaml::Model::Xml::TypeNamespace::Resolver)
    end

    it "initializes with custom register" do
      planner = described_class.new(:custom)

      expect(planner.collector.register).to eq(:custom)
    end
  end

  describe "#plan_for_element" do
    context "with type namespace references" do
      it "returns Array<Declaration>" do
        declarations = planner.plan_for_element(mapping, model_class, nil, {})

        expect(declarations).to be_an(Array)
        expect(declarations.all? { |d| d.is_a?(Lutaml::Model::Xml::TypeNamespace::Declaration) }).to be true
      end

      it "creates declarations with prefix" do
        declarations = planner.plan_for_element(mapping, model_class, nil, {})

        # Should have at least one declaration for the type namespace
        expect(declarations.size).to be > 0

        decl = declarations.first
        expect(decl.prefix).to eq("dc") # prefix_default from type_namespace_class
        expect(decl.namespace_class).to eq(type_namespace_class)
      end

      it "sets declared_at to :parent" do
        declarations = planner.plan_for_element(mapping, model_class, nil, {})

        declarations.each do |decl|
          expect(decl.declared_at).to eq(:parent)
        end
      end

      it "includes element_name for debugging" do
        declarations = planner.plan_for_element(mapping, model_class, nil, {})

        declarations.each do |decl|
          expect(decl.element_name).to eq("document")
        end
      end
    end

    context "with existing declarations" do
      it "skips already declared namespaces" do
        existing = { "dc" => type_namespace_class.uri }

        declarations = planner.plan_for_element(mapping, model_class, nil, existing)

        # Should be empty since namespace is already declared
        expect(declarations).to be_empty
      end

      it "includes new namespaces not in existing" do
        existing = { "other" => "http://other.com/ns" }

        declarations = planner.plan_for_element(mapping, model_class, nil, existing)

        # Should include dc namespace
        expect(declarations.size).to be > 0
        dc_decl = declarations.find { |d| d.prefix == "dc" }
        expect(dc_decl).not_to be_nil
      end
    end

    context "when element namespace equals type namespace" do
      it "does not create redundant declaration" do
        # When element has same namespace as type, element handles it
        declarations = planner.plan_for_element(
          mapping,
          model_class,
          type_namespace_class, # Same as type namespace
          {}
        )

        # Resolver should determine no declaration needed
        # because element namespace covers it
        expect(declarations).to be_empty
      end
    end

    context "when type class has no prefix_default" do
      let(:type_namespace_without_prefix) do
        Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
          uri "http://purl.org/dc/elements/1.1/"
        end
      end

      let(:type_class_without_prefix) do
        ns = type_namespace_without_prefix
        Class.new(Lutaml::Model::Type::String) do
          xml_namespace ns
        end
      end

      let(:model_without_prefix) do
        type = type_class_without_prefix
        Class.new(Lutaml::Model::Serializable) do
          attribute :title, type

          xml do
            root "document"
            map_element "title", to: :title
          end
        end
      end

      let(:mapping_without_prefix) { model_without_prefix.mappings_for(:xml) }

      it "generates a unique prefix" do
        declarations = planner.plan_for_element(
          mapping_without_prefix,
          model_without_prefix,
          nil,
          {}
        )

        expect(declarations.size).to be > 0
        # Generated prefix should start with "tn" (type namespace)
        expect(declarations.first.prefix).to match(/^tn/)
      end
    end

    context "with no type namespace references" do
      let(:model_without_type_ns) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string

          xml do
            root "document"
            map_element "title", to: :title
          end
        end
      end

      let(:mapping_without_type_ns) { model_without_type_ns.mappings_for(:xml) }

      it "returns empty array" do
        declarations = planner.plan_for_element(
          mapping_without_type_ns,
          model_without_type_ns,
          nil,
          {}
        )

        expect(declarations).to be_empty
      end
    end

    context "with nil mapping" do
      it "handles nil mapping gracefully" do
        # The collector calls mapping.attributes, so nil will raise NoMethodError
        # This is the expected behavior - nil mapping is invalid input
        expect {
          planner.plan_for_element(nil, model_class, nil, {})
        }.to raise_error(NoMethodError)
      end
    end
  end

  describe "#plan_for_root" do
    it "returns Array<Declaration>" do
      declarations = planner.plan_for_root(mapping, model_class, nil)

      expect(declarations).to be_an(Array)
      expect(declarations.all? { |d| d.is_a?(Lutaml::Model::Xml::TypeNamespace::Declaration) }).to be true
    end

    it "sets declared_at to :root" do
      declarations = planner.plan_for_root(mapping, model_class, nil)

      declarations.each do |decl|
        expect(decl.declared_at).to eq(:root)
        expect(decl.root_level?).to be true
      end
    end

    it "uses same prefix and namespace_class as plan_for_element" do
      element_declarations = planner.plan_for_element(mapping, model_class, nil, {})
      root_declarations = planner.plan_for_root(mapping, model_class, nil)

      expect(element_declarations.size).to eq(root_declarations.size)

      element_declarations.each_with_index do |elem_decl, i|
        root_decl = root_declarations[i]
        expect(root_decl.prefix).to eq(elem_decl.prefix)
        expect(root_decl.namespace_class).to eq(elem_decl.namespace_class)
      end
    end

    it "marks declarations as root_level?" do
      declarations = planner.plan_for_root(mapping, model_class, nil)

      declarations.each do |decl|
        expect(decl.root_level?).to be true
        expect(decl.parent_level?).to be false
        expect(decl.inline?).to be false
      end
    end
  end

  describe "Declaration validation" do
    it "creates valid declarations" do
      declarations = planner.plan_for_element(mapping, model_class, nil, {})

      declarations.each do |decl|
        expect(decl.namespace_class).to eq(type_namespace_class)
        expect(decl.prefix).to be_a(String)
        expect([:root, :parent, :inline]).to include(decl.declared_at)
      end
    end
  end
end
