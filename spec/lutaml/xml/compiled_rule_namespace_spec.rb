# frozen_string_literal: true

require "spec_helper"

# Test namespace for Type::Value attribute with different URI formats
module TypeValueAttrNsSpec
  # URN namespace
  class VmlNs < Lutaml::Xml::Namespace
    uri "urn:schemas-microsoft-com:vml"
    prefix_default "v"
    attribute_form_default :qualified
  end

  class VmlExtType < Lutaml::Model::Type::String
    xml do
      namespace VmlNs
    end
  end

  # HTTP URI namespace
  class W14Ns < Lutaml::Xml::Namespace
    uri "http://example.com/w14"
    prefix_default "w14"
  end

  class W14ValType < Lutaml::Model::Type::String
    xml do
      namespace W14Ns
    end
  end

  # Simple string namespace (non-URI)
  class MyNs < Lutaml::Xml::Namespace
    uri "my-custom-ns"
    prefix_default "my"
  end

  class MyValType < Lutaml::Model::Type::String
    xml do
      namespace MyNs
    end
  end

  # Models for URN namespace
  class ShapeDefaults < Lutaml::Model::Serializable
    attribute :ext, VmlExtType

    xml do
      element "shapedefaults"
      map_attribute "ext", to: :ext
    end
  end

  # Models for HTTP URI namespace
  class DocId < Lutaml::Model::Serializable
    attribute :val, W14ValType

    xml do
      element "docId"
      namespace W14Ns
      map_attribute "val", to: :val
    end
  end

  # Models for simple string namespace
  class SimpleModel < Lutaml::Model::Serializable
    attribute :val, MyValType

    xml do
      element "root"
      map_attribute "val", to: :val
    end
  end
end

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

RSpec.describe "Type::Value namespace for attribute parsing" do
  describe "parse attribute with type namespace, xmlns declared" do
    it "correctly parses v:ext attribute when xmlns:v is declared" do
      xml = <<~XML
        <shapedefaults xmlns="urn:schemas-microsoft-com:office:office"
                       xmlns:v="urn:schemas-microsoft-com:vml"
                       v:ext="edit"/>
      XML

      obj = TypeValueAttrNsSpec::ShapeDefaults.from_xml(xml)
      expect(obj.ext).to eq("edit")
    end
  end

  describe "parse attribute with type namespace, xmlns NOT declared" do
    it "correctly parses v:ext attribute even without xmlns:v declaration" do
      xml = '<shapedefaults xmlns="urn:schemas-microsoft-com:office:office" v:ext="edit"/>'

      obj = TypeValueAttrNsSpec::ShapeDefaults.from_xml(xml)
      expect(obj.ext).to eq("edit")
    end
  end

  describe "round-trip serialization" do
    it "serializes and re-parses the attribute correctly" do
      obj = TypeValueAttrNsSpec::ShapeDefaults.new(ext: "myvalue")
      serialized = obj.to_xml

      expect(serialized).to include('xmlns:v="urn:schemas-microsoft-com:vml"')
      expect(serialized).to include('v:ext="myvalue"')

      reparsed = TypeValueAttrNsSpec::ShapeDefaults.from_xml(serialized)
      expect(reparsed.ext).to eq("myvalue")
    end
  end

  describe "CompiledRule namespace_class for Type::Value attributes" do
    it "extracts namespace from Type::Value's xml namespace" do
      transformation = TypeValueAttrNsSpec::ShapeDefaults.transformation_for(:xml)
      attr_rules = transformation.compiled_rules.select do |r|
        r.mapping_type == :attribute
      end

      ext_rule = attr_rules.find { |r| r.attribute_name == :ext }
      expect(ext_rule).to be_a(Lutaml::Model::CompiledRule)
      expect(ext_rule.namespace_class).to eq(TypeValueAttrNsSpec::VmlNs)
    end
  end
end

RSpec.describe "Type::Value namespace with different URI formats" do
  describe "URN namespace (urn:schemas-microsoft-com:vml:ext)" do
    it "parses when xmlns is declared" do
      xml = <<~XML
        <shapedefaults xmlns:v="urn:schemas-microsoft-com:vml" v:ext="val1"/>
      XML

      obj = TypeValueAttrNsSpec::ShapeDefaults.from_xml(xml)
      expect(obj.ext).to eq("val1")
    end

    it "parses when xmlns is NOT declared" do
      xml = '<shapedefaults v:ext="val2"/>'

      obj = TypeValueAttrNsSpec::ShapeDefaults.from_xml(xml)
      expect(obj.ext).to eq("val2")
    end

    it "round-trips correctly" do
      obj = TypeValueAttrNsSpec::ShapeDefaults.new(ext: "val3")
      serialized = obj.to_xml
      reparsed = TypeValueAttrNsSpec::ShapeDefaults.from_xml(serialized)
      expect(reparsed.ext).to eq("val3")
    end
  end

  describe "HTTP URI namespace (http://example.com/w14:val)" do
    it "parses when xmlns is declared" do
      xml = <<~XML
        <docId xmlns:w14="http://example.com/w14" w14:val="httpval1"/>
      XML

      obj = TypeValueAttrNsSpec::DocId.from_xml(xml)
      expect(obj.val).to eq("httpval1")
    end

    it "parses when xmlns is NOT declared" do
      xml = '<docId w14:val="httpval2"/>'

      obj = TypeValueAttrNsSpec::DocId.from_xml(xml)
      expect(obj.val).to eq("httpval2")
    end

    it "round-trips correctly" do
      obj = TypeValueAttrNsSpec::DocId.new(val: "httpval3")
      serialized = obj.to_xml
      reparsed = TypeValueAttrNsSpec::DocId.from_xml(serialized)
      expect(reparsed.val).to eq("httpval3")
    end
  end

  describe "simple string namespace (my-custom-ns:val)" do
    it "parses when xmlns is declared" do
      xml = <<~XML
        <root xmlns:my="my-custom-ns" my:val="simpleval1"/>
      XML

      obj = TypeValueAttrNsSpec::SimpleModel.from_xml(xml)
      expect(obj.val).to eq("simpleval1")
    end

    it "parses when xmlns is NOT declared" do
      xml = '<root my:val="simpleval2"/>'

      obj = TypeValueAttrNsSpec::SimpleModel.from_xml(xml)
      expect(obj.val).to eq("simpleval2")
    end

    it "round-trips correctly" do
      obj = TypeValueAttrNsSpec::SimpleModel.new(val: "simpleval3")
      serialized = obj.to_xml
      reparsed = TypeValueAttrNsSpec::SimpleModel.from_xml(serialized)
      expect(reparsed.val).to eq("simpleval3")
    end
  end
end
