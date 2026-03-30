require "spec_helper"
require_relative "../../../lib/lutaml/model"
require_relative "../../../lib/lutaml/xml/type_namespace_resolver"

RSpec.describe "Nil optional element namespace hoisting" do
  # Define a namespace for the child type
  class NilOptChildNamespace < Lutaml::Xml::W3c::XmlNamespace
    uri "http://example.com/child-ns"
    prefix_default "ch"
  end

  # Define a type with namespace (scalar type, not Serializable)
  class NilOptChildType < Lutaml::Model::Type::String
    xml do
      namespace NilOptChildNamespace
    end
  end

  context "when optional typed child is nil (runtime)" do
    it "does NOT include xmlns declaration for the absent child's namespace" do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :child, NilOptChildType

        xml do
          element "parent"
          map_element "child", to: :child
        end
      end

      instance = test_class.new(child: nil)
      xml_output = instance.to_xml

      expect(xml_output).not_to include("xmlns:ch")
      expect(xml_output).not_to include("<ch:child")
      expect(xml_output).not_to include("<child")
    end
  end

  context "when optional typed child is present (runtime)" do
    it "DOES include xmlns declaration for the child's namespace" do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :child, NilOptChildType

        xml do
          element "parent"
          map_element "child", to: :child
        end
      end

      instance = test_class.new(child: "hello")
      xml_output = instance.to_xml

      expect(xml_output).to include('xmlns:ch="http://example.com/child-ns"')
      expect(xml_output).to include("<ch:child>")
      expect(xml_output).to include("hello")
    end
  end

  context "mapping analysis (element is nil)" do
    it "still collects type refs for structural namespace discovery" do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :child, NilOptChildType

        xml do
          element "parent"
          map_element "child", to: :child
        end
      end

      mapping = test_class.mappings_for(:xml)
      collector = Lutaml::Xml::NamespaceCollector.new
      needs = collector.collect(nil, mapping, mapper_class: test_class)

      expect(needs.type_refs).to be_an(Array)
      expect(needs.type_refs.size).to eq(1)

      resolver = Lutaml::Xml::TypeNamespaceResolver.new
      resolver.resolve(needs)

      expect(needs.type_namespace_classes).to include(NilOptChildNamespace)
      expect(needs.type_namespaces[:child]).to eq(NilOptChildNamespace)
    end
  end
end
