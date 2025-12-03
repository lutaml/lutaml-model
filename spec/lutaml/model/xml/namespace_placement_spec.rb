# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML Namespace Placement" do
  # Ensure adapter is always reset after each example to prevent pollution
  after(:each) do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  context "when namespace is at class level (Type::Value)" do
    it "applies namespace to value types correctly" do
      ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/ns"
        prefix_default "ex"
      end

      value_type = Class.new(Lutaml::Model::Type::String) do
        namespace ns
      end

      model = Class.new do
        include Lutaml::Model::Serialize

        attribute :name, value_type

        xml do
          root "model"
          namespace ns
          map_element "name", to: :name
        end
      end

      instance = model.new(name: "test")
      xml = instance.to_xml(prefix: true)

      expect(xml).to include("<ex:model")
      expect(xml).to include("<ex:name>test</ex:name>")
    end
  end

  context "when namespace is inside xml block (Serializable/Model)" do
    it "applies namespace to nested model elements correctly" do
      parent_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/parent"
        prefix_default "parent"
      end

      child_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/child"
        prefix_default "child"
      end

      child_model = Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :string

        xml do
          root "nested"
          namespace child_ns
          map_content to: :value
        end
      end

      parent_model = Class.new do
        include Lutaml::Model::Serialize

        attribute :child, child_model

        xml do
          root "parent"
          namespace parent_ns
          namespace_scope [parent_ns, child_ns]
          map_element "nested", to: :child
        end
      end

      instance = parent_model.new(child: child_model.new(value: "test"))
      xml = instance.to_xml(prefix: true)

      expect(xml).to include("<parent:parent")
      expect(xml).to include("<child:nested>test</child:nested>")
    end
  end

  context "when namespace is at class level for Serializable (INCORRECT)" do
    it "does NOT apply namespace - demonstrating the incorrect pattern" do
      ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/ns"
        prefix_default "ex"
      end

      # This is the INCORRECT pattern - namespace at class level for Models
      broken_model = Class.new do
        include Lutaml::Model::Serialize

        namespace ns # ❌ This doesn't work for Serializable classes!

        attribute :value, :string

        xml do
          root "broken"
          map_content to: :value
        end
      end

      parent_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/parent"
        prefix_default "parent"
      end

      parent_model = Class.new do
        include Lutaml::Model::Serialize

        attribute :child, broken_model

        xml do
          root "parent"
          namespace parent_ns
          namespace_scope [parent_ns, ns]
          map_element "broken", to: :child
        end
      end

      instance = parent_model.new(child: broken_model.new(value: "test"))
      xml = instance.to_xml(prefix: true)

      # The namespace prefix is NOT applied because namespace was at class level
      expect(xml).to include("<parent:parent")
      expect(xml).to include("<broken>test</broken>") # No ex: prefix!
      expect(xml).not_to include("<ex:broken>")
    end
  end

  context "real-world example: Dublin Core Terms with xsi:type" do
    it "correctly applies dcterms namespace when declared in xml block" do
      dcterms_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://purl.org/dc/terms/"
        prefix_default "dcterms"
      end

      xsi_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://www.w3.org/2001/XMLSchema-instance"
        prefix_default "xsi"
      end

      cp_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
        prefix_default "cp"
        element_form_default :qualified
      end

      xsi_type = Class.new(Lutaml::Model::Type::String) do
        namespace xsi_ns
      end

      created_type = Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :date_time
        attribute :type, xsi_type

        xml do
          root "created"
          namespace dcterms_ns # ✅ CORRECT: namespace in xml block
          map_attribute "type", to: :type
          map_content to: :value
        end
      end

      core_properties = Class.new do
        include Lutaml::Model::Serialize

        attribute :title, :string
        attribute :created, created_type

        xml do
          root "coreProperties"
          namespace cp_ns
          namespace_scope [cp_ns, dcterms_ns, xsi_ns]
          map_element "title", to: :title
          map_element "created", to: :created
        end
      end

      now = DateTime.parse("2025-01-15T10:00:00+08:00")
      instance = core_properties.new(
        title: "Test",
        created: created_type.new(value: now, type: "dcterms:W3CDTF"),
      )

      xml = instance.to_xml(prefix: true)

      # Verify correct namespace prefixes
      expect(xml).to include("<cp:coreProperties")
      expect(xml).to include("<cp:title>Test</cp:title>")
      expect(xml).to include("<dcterms:created")
      expect(xml).to include('xsi:type="dcterms:W3CDTF"')
      expect(xml).to include("</dcterms:created>")
    end
  end

  context "summary of namespace placement rules" do
    it "documents the correct patterns" do
      # Pattern 1: Type::Value classes - namespace at CLASS level
      type_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/type"
        prefix_default "type"
      end

      custom_type = Class.new(Lutaml::Model::Type::String) do
        namespace type_ns # ✅ Correct for Type::Value
      end

      # Pattern 2: Serializable classes - namespace in XML block
      model_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/model"
        prefix_default "model"
      end

      nested_model = Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :string

        xml do
          root "nested"
          namespace model_ns # ✅ Correct for Serializable
          map_content to: :value
        end
      end

      # Pattern 3: Parent model with namespace_scope
      parent_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/parent"
        prefix_default "parent"
      end

      parent_model = Class.new do
        include Lutaml::Model::Serialize

        attribute :type_attr, custom_type
        attribute :model_attr, nested_model

        xml do
          root "parent"
          namespace parent_ns
          namespace_scope [parent_ns, type_ns, model_ns]
          map_element "typeAttr", to: :type_attr
          map_element "nested", to: :model_attr
        end
      end

      instance = parent_model.new(
        type_attr: "type_value",
        model_attr: nested_model.new(value: "model_value"),
      )

      xml = instance.to_xml(prefix: true)

      # All namespaces should be correctly applied
      expect(xml).to include("<parent:parent")
      expect(xml).to include("<type:typeAttr>type_value</type:typeAttr>")
      expect(xml).to include("<model:nested>model_value</model:nested>")
    end
  end
end
