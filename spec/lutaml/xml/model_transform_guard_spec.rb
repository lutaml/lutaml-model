# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

RSpec.describe "ModelTransform name conversion guard specs" do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :ns_attr, :string

      xml do
        root "root"
        map_element "name", to: :name
        map_attribute "ex:attr", to: :ns_attr
      end

      def self.name
        "NameConversionTestModel"
      end
    end
  end

  describe "rindex-based name splitting" do
    it "correctly handles URI-format namespaced attributes" do
      xml = <<~XML
        <root xmlns:ex="http://example.com/ns"
              ex:attr="value"
              name="test"/>
      XML
      result = model_class.from_xml(xml)
      expect(result.ns_attr).to eq("value")
    end

    it "correctly handles prefix-format namespaced attributes" do
      xml = <<~XML
        <root xmlns:ex="http://example.com/ns"
              ex:attr="prefixed_value"
              name="test"/>
      XML
      result = model_class.from_xml(xml)
      expect(result.ns_attr).to eq("prefixed_value")
    end

    it "handles element name matching without namespace" do
      xml = "<root><name>John</name></root>"
      result = model_class.from_xml(xml)
      expect(result.name).to eq("John")
    end

    it "handles deeply nested elements with namespaces" do
      nested_class = Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          root "nested"
          map_content to: :value
        end

        def self.name
          "NestedModel"
        end
      end

      parent_class = Class.new(Lutaml::Model::Serializable) do
        attribute :child, nested_class

        xml do
          root "parent"
          map_element "child", to: :child
        end

        def self.name
          "ParentModel"
        end
      end

      xml = <<~XML
        <parent xmlns:ns="http://example.com">
          <child>hello</child>
        </parent>
      XML
      result = parent_class.from_xml(xml)
      expect(result.child.value).to eq("hello")
    end
  end

  describe "map replacing filter_map" do
    it "correctly maps all attribute names including converted ones" do
      xml = <<~XML
        <root xmlns:ex="http://example.com/ns"
              ex:attr="converted">
          <name>test</name>
        </root>
      XML
      result = model_class.from_xml(xml)
      expect(result.ns_attr).to eq("converted")
      expect(result.name).to eq("test")
    end

    it "handles multiple namespace-prefixed attributes" do
      multi_class = Class.new(Lutaml::Model::Serializable) do
        attribute :a, :string
        attribute :b, :string

        xml do
          root "root"
          map_attribute "ns:a", to: :a
          map_attribute "ns:b", to: :b
        end

        def self.name
          "MultiAttrModel"
        end
      end

      xml = <<~XML
        <root xmlns:ns="http://example.com"
              ns:a="val_a" ns:b="val_b"/>
      XML
      result = multi_class.from_xml(xml)
      expect(result.a).to eq("val_a")
      expect(result.b).to eq("val_b")
    end
  end
end
