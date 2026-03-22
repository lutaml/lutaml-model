# frozen_string_literal: true

require "spec_helper"

# Test namespace for same-named elements
module SameNamedNsSpec
  class W14Ns < Lutaml::Xml::Namespace
    uri "http://example.com/w14"
    prefix_default "w14"
    element_form_default :qualified
  end

  class W15Ns < Lutaml::Xml::Namespace
    uri "http://example.com/w15"
    prefix_default "w15"
    element_form_default :qualified
  end

  class RootNs < Lutaml::Xml::Namespace
    uri "http://example.com/root"
    prefix_default "r"
    element_form_default :qualified
  end

  # W14 DocId model (in w14 namespace)
  class W14DocId < Lutaml::Model::Serializable
    attribute :val, :string

    xml do
      element "docId"
      namespace W14Ns
      map_attribute "val", to: :val
    end
  end

  # W15 DocId model (in w15 namespace)
  class W15DocId < Lutaml::Model::Serializable
    attribute :val, :string

    xml do
      element "docId"
      namespace W15Ns
      map_attribute "val", to: :val
    end
  end

  # Parent with two same-named map_element entries
  class Settings < Lutaml::Model::Serializable
    attribute :w14_doc_id, W14DocId
    attribute :w15_doc_id, W15DocId

    xml do
      element "settings"
      namespace RootNs
      namespace_scope [W14Ns, W15Ns]

      map_element "docId", to: :w14_doc_id
      map_element "docId", to: :w15_doc_id
    end
  end

  # Nested model with Serializable attribute (for delegated rule tests)
  class Container < Lutaml::Model::Serializable
    attribute :inner, W14DocId

    xml do
      element "container"
      namespace RootNs
      map_element "inner", to: :inner
    end
  end
end

# Serializable attribute mapped as XML attribute (for attribute rule test)
module SerializableAttrNsSpec
  class InnerNs < Lutaml::Xml::Namespace
    uri "http://inner.com"
    prefix_default "in"
    attribute_form_default :qualified
  end

  class InnerModel < Lutaml::Model::Serializable
    attribute :code, :string

    xml do
      element "inner"
      namespace InnerNs
      map_content to: :code
    end
  end

  class OuterModel < Lutaml::Model::Serializable
    attribute :inner, InnerModel

    xml do
      element "outer"
      map_attribute "inner", to: :inner
    end
  end
end

RSpec.describe "CompiledRule namespace_class for Serializable model attributes" do
  describe "compile_standard_element_rule" do
    it "extracts namespace from Serializable model's XML mapping" do
      transformation = SameNamedNsSpec::Settings.transformation_for(:xml)
      rules = transformation.compiled_rules

      w14_rule = rules.find { |r| r.attribute_name == :w14_doc_id }
      w15_rule = rules.find { |r| r.attribute_name == :w15_doc_id }

      expect(w14_rule).to be_a(Lutaml::Model::CompiledRule)
      expect(w14_rule.namespace_class).to eq(SameNamedNsSpec::W14Ns)

      expect(w15_rule).to be_a(Lutaml::Model::CompiledRule)
      expect(w15_rule.namespace_class).to eq(SameNamedNsSpec::W15Ns)
    end
  end

  describe "compile_standard_attribute_rule" do
    it "extracts namespace from Serializable model's XML mapping" do
      transformation = SerializableAttrNsSpec::OuterModel.transformation_for(:xml)
      attr_rules = transformation.compiled_rules.select do |r|
        r.mapping_type == :attribute
      end

      inner_rule = attr_rules.find { |r| r.attribute_name == :inner }
      expect(inner_rule).to be_a(Lutaml::Model::CompiledRule)
      expect(inner_rule.namespace_class).to eq(SerializableAttrNsSpec::InnerNs)
    end
  end

  describe "round-trip serialization for same-named elements" do
    it "correctly serializes two docId elements to different namespaces" do
      xml = <<~XML
        <r:settings xmlns:r="http://example.com/root"
                    xmlns:w14="http://example.com/w14"
                    xmlns:w15="http://example.com/w15">
          <w14:docId w14:val="12345"/>
          <w15:docId w15:val="67890"/>
        </r:settings>
      XML

      settings = SameNamedNsSpec::Settings.from_xml(xml)

      expect(settings.w14_doc_id).to be_a(SameNamedNsSpec::W14DocId)
      expect(settings.w14_doc_id.val).to eq("12345")
      expect(settings.w15_doc_id).to be_a(SameNamedNsSpec::W15DocId)
      expect(settings.w15_doc_id.val).to eq("67890")

      # Round-trip: serialize and re-parse
      serialized = settings.to_xml
      reparsed = SameNamedNsSpec::Settings.from_xml(serialized)

      expect(reparsed.w14_doc_id.val).to eq("12345")
      expect(reparsed.w15_doc_id.val).to eq("67890")

      # Verify correct namespace prefixes in output
      expect(serialized).to include("<w14:docId")
      expect(serialized).to include("<w15:docId")
    end

    it "serializes with both docId elements when both are present" do
      settings = SameNamedNsSpec::Settings.new(
        w14_doc_id: SameNamedNsSpec::W14DocId.new(val: "W14-VALUE"),
        w15_doc_id: SameNamedNsSpec::W15DocId.new(val: "W15-VALUE"),
      )

      serialized = settings.to_xml

      # Both elements should appear with correct namespaces
      expect(serialized.scan(/<w14:docId[^>]*>/).size).to eq(1)
      expect(serialized.scan(/<w15:docId[^>]*>/).size).to eq(1)

      # Parse back
      reparsed = SameNamedNsSpec::Settings.from_xml(serialized)
      expect(reparsed.w14_doc_id.val).to eq("W14-VALUE")
      expect(reparsed.w15_doc_id.val).to eq("W15-VALUE")
    end

    it "handles parsing with default namespace format" do
      xml = <<~XML
        <settings xmlns="http://example.com/root"
                  xmlns:w14="http://example.com/w14"
                  xmlns:w15="http://example.com/w15">
          <w14:docId w14:val="ABC"/>
          <w15:docId w15:val="DEF"/>
        </settings>
      XML

      settings = SameNamedNsSpec::Settings.from_xml(xml)
      expect(settings.w14_doc_id.val).to eq("ABC")
      expect(settings.w15_doc_id.val).to eq("DEF")
    end

    it "serializes correctly with prefix: true" do
      settings = SameNamedNsSpec::Settings.new(
        w14_doc_id: SameNamedNsSpec::W14DocId.new(val: "X"),
        w15_doc_id: SameNamedNsSpec::W15DocId.new(val: "Y"),
      )

      serialized = settings.to_xml(prefix: true)

      expect(serialized).to include("w14:docId")
      expect(serialized).to include("w15:docId")
    end
  end
end
