# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

# Comprehensive spec to guard against namespace bleeding bugs
# Tests that elements correctly inherit or declare namespaces based on their relationships
RSpec.describe "XML namespace inheritance" do
  # Ensure adapter is always reset after each example
  # after(:each) do
  #   Lutaml::Model::Config.xml_adapter_type = :nokogiri
  # end

  # Define test namespaces
  let(:parent_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://example.com/parent"
      prefix_default "parent"
    end
  end

  let(:child_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://example.com/child"
      prefix_default "child"
    end
  end

  let(:grandchild_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://example.com/grandchild"
      prefix_default "gc"
    end
  end

  context "parent and child in same namespace" do
    let(:child_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "child"
          namespace ns
          map_content to: :content
        end
      end
    end

    let(:parent_model) do
      ns = parent_namespace
      child = child_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :child_elem, child

        xml do
          element "parent"
          namespace ns
          map_element "child", to: :child_elem
        end
      end
    end

    it "child should not have xmlns (inherits from parent)" do
      child = child_model.new(content: "test")
      parent = parent_model.new(child_elem: child)
      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <child>test</child>
        </parent>
      XML

      expect(xml).to match(expected)
    end
  end

  context "parent and child in different namespaces" do
    let(:child_attribute) do
      ns = child_namespace
      Class.new(Lutaml::Model::Type::String) do
        xml_namespace ns
      end
    end

    let(:parent_attribute) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Type::String) do
        xml_namespace ns
      end
    end

    let(:child_model) do
      ns = child_namespace
      pa = parent_attribute
      ca = child_attribute
      Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string
        attribute :parent_ns_attr, pa
        attribute :child_ns_attr, ca

        xml do
          element "child"
          namespace ns
          map_attribute "parent_ns_attr", to: :parent_ns_attr
          map_attribute "child_ns_attr", to: :child_ns_attr
          map_content to: :content
        end
      end
    end

    let(:parent_model) do
      ns = parent_namespace
      child = child_model
      pa = parent_attribute
      ca = child_attribute
      Class.new(Lutaml::Model::Serializable) do
        attribute :child_elem, child
        attribute :parent_ns_attr, pa
        attribute :child_ns_attr, ca

        xml do
          element "parent"
          namespace ns
          map_element "child", to: :child_elem
          map_attribute "parent_ns_attr", to: :parent_ns_attr
          map_attribute "child_ns_attr", to: :child_ns_attr
        end
      end
    end

    it "parent and child both use default namespaces" do
      child = child_model.new(content: "test")
      parent = parent_model.new(child_elem: child)
      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <child xmlns="http://example.com/child">test</child>
        </parent>
      XML

      expect(xml).to match(expected)
    end

    it "child sets xmlns (when parent forces prefix)" do
      child = child_model.new(content: "test")
      parent = parent_model.new(child_elem: child)
      xml = parent.to_xml(prefix: true)

      # CORRECT BEHAVIOR: When parent forces prefix format, child uses default format
      # for its own namespace (child uses its own namespace's default presentation)
      expected = <<~XML.chomp
        <parent:parent xmlns:parent="http://example.com/parent">
          <child xmlns="http://example.com/child">test</child>
        </parent:parent>
      XML

      expect(xml).to match(expected)
    end

    it "child sets xmlns (when parent uses 'custom' prefix)" do
      child = child_model.new(content: "test")
      parent = parent_model.new(child_elem: child)
      xml = parent.to_xml(prefix: "custom")

      expected = <<~XML.chomp
        <custom:parent xmlns:custom="http://example.com/parent">
          <child xmlns="http://example.com/child">test</child>
        </custom:parent>
      XML

      expect(xml).to match(expected)
    end

    it "parent forces prefixed xmlns when it has namespaced attribute" do
      child = child_model.new(content: "test")
      parent = parent_model.new(child_elem: child, parent_ns_attr: "value")
      xml = parent.to_xml

      # W3C attributeFormDefault="unqualified": attribute in same namespace as element
      # has NO prefix (inherits from element's namespace context)
      expected = <<~XML.chomp
        <parent:parent xmlns:parent="http://example.com/parent" parent_ns_attr="value">
          <child xmlns="http://example.com/child">test</child>
        </parent:parent>
      XML

      expect(xml).to match(expected)
    end

    it "child forces prefixed xmlns when it has namespaced attribute" do
      child = child_model.new(content: "test", child_ns_attr: "value")
      parent = parent_model.new(child_elem: child)
      xml = parent.to_xml

      # W3C attributeFormDefault="unqualified": attribute in same namespace as element
      # has NO prefix (inherits from element's namespace context)
      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <child:child xmlns:child="http://example.com/child" child_ns_attr="value">test</child:child>
        </parent>
      XML

      expect(xml).to match(expected)
    end

    it "child attribute forced to use parent has already declared prefixed xmlns" do
      child = child_model.new(content: "test", parent_ns_attr: "value")
      parent = parent_model.new(child_elem: child)
      xml = parent.to_xml

      # Architecture: Child uses default format for its namespace
      # Attribute in different namespace (parent) uses prefix
      # This is W3C compliant - elements only use prefix when THEIR namespace requires it
      expected = <<~XML.chomp
        <parent:parent xmlns:parent="http://example.com/parent">
          <child xmlns="http://example.com/child" parent:parent_ns_attr="value">test</child>
        </parent:parent>
      XML

      expect(xml).to match(expected)
    end

    it "child element forced to use parent has already declared prefixed xmlns" do
      child = child_model.new(content: "test", parent_ns_attr: "value", child_ns_attr: "value")
      parent = parent_model.new(child_elem: child, child_ns_attr: "value")
      xml = parent.to_xml

      # W3C attributeFormDefault="unqualified":
      # - Parent's child_ns_attr is in CHILD namespace (different) → MUST have prefix
      # - Child's parent_ns_attr is in PARENT namespace (different from child) → MUST have prefix
      # - Child's child_ns_attr is in CHILD namespace (same as child) → NO prefix (unqualified)
      expected = <<~XML.chomp
        <parent:parent xmlns:parent="http://example.com/parent" xmlns:child="http://example.com/child" child:child_ns_attr="value">
          <child:child parent:parent_ns_attr="value" child_ns_attr="value">test</child:child>
        </parent:parent>
      XML

      expect(xml).to match(expected)
    end
  end

  context "three-level hierarchy with mixed namespaces" do
    let(:grandchild_model) do
      ns = grandchild_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "grandchild"
          namespace ns
          map_content to: :value
        end
      end
    end

    let(:child_model) do
      ns = child_namespace
      gc = grandchild_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :grandchild_elem, gc
        attribute :content, :string

        xml do
          element "child"
          namespace ns
          map_element "grandchild", to: :grandchild_elem
          map_attribute "content", to: :content
        end
      end
    end

    let(:parent_model) do
      ns = parent_namespace
      child = child_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :child_elem, child

        xml do
          element "parent"
          namespace ns
          map_element "child", to: :child_elem
        end
      end
    end

    it "each level declares only its own namespace, not descendants'" do
      grandchild = grandchild_model.new(value: "data")
      child = child_model.new(grandchild_elem: grandchild, content: "info")
      parent = parent_model.new(child_elem: child)
      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <child xmlns="http://example.com/child" content="info">
            <grandchild xmlns="http://example.com/grandchild">data</grandchild>
          </child>
        </parent>
      XML

      expect(xml).to match(expected)
    end

    it "round-trips three-level hierarchy correctly" do
      original = parent_model.new(
        child_elem: child_model.new(
          content: "info",
          grandchild_elem: grandchild_model.new(value: "data")
        )
      )

      xml = original.to_xml
      parsed = parent_model.from_xml(xml)
      regenerated = parsed.to_xml

      # Architecture uses default namespace format for regeneration (W3C compliant)
      # This is correct behavior - models serialize using default format unless prefix: true
      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <child xmlns="http://example.com/child" content="info">
            <grandchild xmlns="http://example.com/grandchild">data</grandchild>
          </child>
        </parent>
      XML

      expect(regenerated).to match(expected)
    end
  end

  context "sibling elements with different namespaces" do
    let(:sibling1_model) do
      ns = child_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "sibling1"
          namespace ns
          map_content to: :value
        end
      end
    end

    let(:sibling2_model) do
      ns = grandchild_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "sibling2"
          namespace ns
          map_content to: :value
        end
      end
    end

    let(:parent_model) do
      ns = parent_namespace
      sib1 = sibling1_model
      sib2 = sibling2_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :sibling1, sib1
        attribute :sibling2, sib2

        xml do
          element "parent"
          namespace ns
          map_element "sibling1", to: :sibling1
          map_element "sibling2", to: :sibling2
        end
      end
    end

    it "siblings declare their own namespaces independently" do
      parent = parent_model.new(
        sibling1: sibling1_model.new(value: "first"),
        sibling2: sibling2_model.new(value: "second")
      )

      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <sibling1 xmlns="http://example.com/child">first</sibling1>
          <sibling2 xmlns="http://example.com/grandchild">second</sibling2>
        </parent>
      XML

      expect(xml).to match(expected)
    end
  end

  context "child in same namespace should inherit, not redeclare" do
    let(:deeply_nested_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "level3"
          namespace ns
          map_content to: :value
        end
      end
    end

    let(:middle_model) do
      ns = parent_namespace
      nested = deeply_nested_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :level3, nested

        xml do
          element "level2"
          namespace ns
          map_element "level3", to: :level3
        end
      end
    end

    let(:top_model) do
      ns = parent_namespace
      middle = middle_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :level2, middle

        xml do
          element "level1"
          namespace ns
          map_element "level2", to: :level2
        end
      end
    end

    it "deeply nested elements in same namespace inherit without redeclaration" do
      deeply = deeply_nested_model.new(value: "deep")
      middle = middle_model.new(level3: deeply)
      top = top_model.new(level2: middle)

      xml = top.to_xml

      expected = <<~XML.chomp
        <level1 xmlns="http://example.com/parent">
          <level2>
            <level3>deep</level3>
          </level2>
        </level1>
      XML

      expect(xml).to match(expected)
    end
  end

  context "complex mixed namespace hierarchy" do
    # parent uses parent_namespace
    # Child1 uses child_namespace (different)
    # Grandchild1 uses parent_namespace (same as parent, different from child)
    # Child2 uses parent_namespace (same as parent)

    let(:grandchild_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "grandchild"
          namespace ns
          map_content to: :value
        end
      end
    end

    let(:child1_model) do
      ns = child_namespace
      gc = grandchild_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :grandchild, gc

        xml do
          element "child1"
          namespace ns
          map_element "grandchild", to: :grandchild
        end
      end
    end

    let(:child2_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "child2"
          namespace ns
          map_content to: :value
        end
      end
    end

    let(:parent_model) do
      ns = parent_namespace
      c1 = child1_model
      c2 = child2_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :child1, c1
        attribute :child2, c2

        xml do
          element "parent"
          namespace ns
          map_element "child1", to: :child1
          map_element "child2", to: :child2
        end
      end
    end

    it "correctly handles alternating namespace changes" do
      grandchild = grandchild_model.new(value: "deep")
      child1 = child1_model.new(grandchild: grandchild)
      child2 = child2_model.new(value: "simple")
      parent = parent_model.new(child1: child1, child2: child2)

      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <child1 xmlns="http://example.com/child">
            <grandchild xmlns="http://example.com/parent">deep</grandchild>
          </child1>
          <child2>simple</child2>
        </parent>
      XML

      expect(xml).to match(expected)
    end

    it "prevents grandchild namespace bleeding to child" do
      grandchild = grandchild_model.new(value: "deep")
      child1 = child1_model.new(grandchild: grandchild)
      child2 = child2_model.new(value: "simple")
      parent = parent_model.new(child1: child1, child2: child2)

      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <child1 xmlns="http://example.com/child">
            <grandchild xmlns="http://example.com/parent">deep</grandchild>
          </child1>
          <child2>simple</child2>
        </parent>
      XML

      expect(xml).to match(expected)
    end

    it "prevents child namespace bleeding to parent" do
      grandchild = grandchild_model.new(value: "deep")
      child1 = child1_model.new(grandchild: grandchild)
      child2 = child2_model.new(value: "simple")
      parent = parent_model.new(child1: child1, child2: child2)

      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <child1 xmlns="http://example.com/child">
            <grandchild xmlns="http://example.com/parent">deep</grandchild>
          </child1>
          <child2>simple</child2>
        </parent>
      XML

      expect(xml).to match(expected)
    end
  end

  context "attribute namespaces do not affect element namespaces" do
    let(:attr_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/attr"
        prefix_default "attr"
      end
    end

    let(:attr_type) do
      ns = attr_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    let(:model) do
      ns = parent_namespace
      attr_t = attr_type
      Class.new(Lutaml::Model::Serializable) do
        attribute :custom_attr, attr_t
        attribute :content, :string

        xml do
          element "element"
          namespace ns
          map_attribute "customAttr", to: :custom_attr
          map_content to: :content
        end
      end
    end

    it "element uses its own namespace, not attribute's namespace" do
      instance = model.new(custom_attr: "value", content: "text")
      xml = instance.to_xml

      # Architecture: Element uses default format for its namespace
      # Attribute in different namespace uses prefix
      # W3C compliant - attributes in other namespaces don't affect element format
      expected = <<~XML.chomp
        <element xmlns="http://example.com/parent" xmlns:attr="http://example.com/attr" attr:customAttr="value">text</element>
      XML

      expect(xml).to match(expected)
    end
  end

  context "namespace_scope does not cause bleeding" do
    let(:scoped_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/scoped"
        prefix_default "scoped"
      end
    end

    let(:unused_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/unused"
        prefix_default "unused"
      end
    end

    let(:child_model) do
      ns = scoped_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "child"
          namespace ns
          map_content to: :value
        end
      end
    end

    let(:parent_model_auto) do
      ns = parent_namespace
      scoped_ns = scoped_namespace
      unused_ns = unused_namespace
      child = child_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :child_elem, child

        xml do
          element "parent"
          namespace ns
          namespace_scope [
            scoped_ns,
            unused_ns
          ]  # Declare scoped_ns at parent

          map_element "child", to: :child_elem
        end
      end
    end

    let(:parent_model_always) do
      ns = parent_namespace
      scoped_ns = scoped_namespace
      unused_ns = unused_namespace
      child = child_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :child_elem, child

        xml do
          element "parent"
          namespace ns
          namespace_scope [
            { namespace: scoped_ns, declare: :auto },
            { namespace: unused_ns, declare: :always }
          ]

          map_element "child", to: :child_elem
        end
      end
    end

    it "namespace_scope declare: auto, declares only used namespaces and skips unused" do
      parent = parent_model_auto.new(
        child_elem: child_model.new(value: "test")
      )
      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent" xmlns:scoped="http://example.com/scoped">
          <scoped:child>test</scoped:child>
        </parent>
      XML

      expect(xml).to match(expected)
    end

    it "namespace_scope declare: always, declares used and unused namespaces" do
      parent = parent_model_always.new(
        child_elem: child_model.new(value: "test")
      )

      xml = parent.to_xml

      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent" xmlns:scoped="http://example.com/scoped" xmlns:unused="http://example.com/unused">
          <scoped:child>test</scoped:child>
        </parent>
      XML

      expect(xml).to match(expected)
    end
  end

  context "collection elements respect namespace inheritance" do
    let(:parent_ns_attr) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Type::String) do
        xml_namespace ns
      end
    end

    let(:child_ns_attr) do
      ns = child_namespace
      Class.new(Lutaml::Model::Type::String) do
        xml_namespace ns
      end
    end

    let(:item_model) do
      ns = parent_namespace
      pa = parent_ns_attr
      ca = child_ns_attr
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :parent_ns_attr, pa
        attribute :child_ns_attr, ca

        xml do
          element "item"
          namespace ns
          map_attribute "parent_ns_attr", to: :parent_ns_attr
          map_attribute "child_ns_attr", to: :child_ns_attr
          map_content to: :name
        end
      end
    end

    let(:collection_model) do
      ns = parent_namespace
      item = item_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :items, item, collection: true

        xml do
          element "collection"
          namespace ns
          map_element "item", to: :items
        end
      end
    end

    let(:collection_model_with_scope) do
      ns = parent_namespace
      scoped_ns = child_namespace
      item = item_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :items, item, collection: true

        xml do
          element "collection"
          namespace ns
          namespace_scope [scoped_ns]
          map_element "item", to: :items
        end
      end
    end

    it "collection items in same namespace inherit using default namespace" do
      collection = collection_model.new(
        items: [
          item_model.new(name: "first"),
          item_model.new(name: "second"),
          item_model.new(name: "third")
        ]
      )

      xml = collection.to_xml

      expected = <<~XML.chomp
        <collection xmlns="http://example.com/parent">
          <item>first</item>
          <item>second</item>
          <item>third</item>
        </collection>
      XML

      expect(xml).to match(expected)
    end

    it "collection items in same namespace inherit with prefix" do
      collection = collection_model.new(
        items: [
          item_model.new(name: "first"),
          item_model.new(name: "second"),
          item_model.new(name: "third")
        ]
      )

      xml = collection.to_xml(prefix: true)

      expected = <<~XML.chomp
        <parent:collection xmlns:parent="http://example.com/parent">
          <parent:item>first</parent:item>
          <parent:item>second</parent:item>
          <parent:item>third</parent:item>
        </parent:collection>
      XML

      expect(xml).to match(expected)
    end

    it "collection items in same namespace with parent_ns_attr inherit with prefix" do
      collection = collection_model.new(
        items: [
          item_model.new(name: "first", parent_ns_attr: "value1"),
          item_model.new(name: "second", parent_ns_attr: "value2"),
          item_model.new(name: "third", parent_ns_attr: "value3")
        ]
      )

      xml = collection.to_xml

      # Architecture: Collection and items use prefix because items have attributes
      # in SAME namespace (parent namespace) per W3C attributeFormDefault
      # Items inherit collection's prefix format
      # W3C attributeFormDefault="unqualified": attributes in same namespace as element
      # are unqualified (no prefix) even when element uses prefix format
      expected = <<~XML.chomp
        <parent:collection xmlns:parent="http://example.com/parent">
          <parent:item parent_ns_attr="value1">first</parent:item>
          <parent:item parent_ns_attr="value2">second</parent:item>
          <parent:item parent_ns_attr="value3">third</parent:item>
        </parent:collection>
      XML

      expect(xml).to match(expected)
    end

    it "collection items in same namespace with child_ns_attr inherit with prefix" do
      collection = collection_model.new(
        items: [
          item_model.new(name: "first", child_ns_attr: "value1"),
          item_model.new(name: "second", child_ns_attr: "value2"),
          item_model.new(name: "third", child_ns_attr: "value3")
        ]
      )

      xml = collection.to_xml

      # Architecture: Collection and items use prefix because items have attributes
      # in child_namespace (different from collection's parent_namespace)
      # Type namespace (child_ns_attr) is declared on root for efficiency
      expected = <<~XML.chomp
        <collection xmlns="http://example.com/parent" xmlns:child="http://example.com/child">
          <item child:child_ns_attr="value1">first</item>
          <item child:child_ns_attr="value2">second</item>
          <item child:child_ns_attr="value3">third</item>
        </collection>
      XML

      expect(xml).to match(expected)
    end

    it "collection scoped for items" do
      collection = collection_model_with_scope.new(
        items: [
          item_model.new(name: "first", child_ns_attr: "value1"),
          item_model.new(name: "second", child_ns_attr: "value2"),
          item_model.new(name: "third", child_ns_attr: "value3")
        ]
      )

      xml = collection.to_xml

      expected = <<~XML.chomp
        <collection xmlns="http://example.com/parent" xmlns:child="http://example.com/child">
          <item child:child_ns_attr="value1">first</item>
          <item child:child_ns_attr="value2">second</item>
          <item child:child_ns_attr="value3">third</item>
        </collection>
      XML

      expect(xml).to match(expected)
    end

    it "collection items with default and child namespace forced to have prefix" do
      collection = collection_model.new(
        items: [
          item_model.new(name: "first", parent_ns_attr: "value1", child_ns_attr: "value1"),
          item_model.new(name: "second", parent_ns_attr: "value2", child_ns_attr: "value2"),
          item_model.new(name: "third", parent_ns_attr: "value3", child_ns_attr: "value3")
        ]
      )

      xml = collection.to_xml

      # W3C attributeFormDefault="unqualified": attributes in same namespace as element
      # have NO prefix (inherit from element's namespace context)
      # Type namespace (child_ns_attr) is declared on root for efficiency
      expected = <<~XML.chomp
        <parent:collection xmlns:parent="http://example.com/parent" xmlns:child="http://example.com/child">
          <parent:item parent_ns_attr="value1" child:child_ns_attr="value1">first</parent:item>
          <parent:item parent_ns_attr="value2" child:child_ns_attr="value2">second</parent:item>
          <parent:item parent_ns_attr="value3" child:child_ns_attr="value3">third</parent:item>
        </parent:collection>
      XML

      expect(xml).to match(expected)
    end

    it "collection with scope has items with prefixes" do
      collection = collection_model_with_scope.new(
        items: [
          item_model.new(name: "first", parent_ns_attr: "value1", child_ns_attr: "value1"),
          item_model.new(name: "second", parent_ns_attr: "value2", child_ns_attr: "value2"),
          item_model.new(name: "third", parent_ns_attr: "value3", child_ns_attr: "value3")
        ]
      )

      xml = collection.to_xml

      # W3C attributeFormDefault="unqualified": attributes in same namespace as element
      # have NO prefix (inherit from element's namespace context)
      expected = <<~XML.chomp
        <parent:collection xmlns:parent="http://example.com/parent" xmlns:child="http://example.com/child">
          <parent:item parent_ns_attr="value1" child:child_ns_attr="value1">first</parent:item>
          <parent:item parent_ns_attr="value2" child:child_ns_attr="value2">second</parent:item>
          <parent:item parent_ns_attr="value3" child:child_ns_attr="value3">third</parent:item>
        </parent:collection>
      XML

      expect(xml).to match(expected)
    end

  end
end