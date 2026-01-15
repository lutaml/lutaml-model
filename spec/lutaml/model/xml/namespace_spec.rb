require "spec_helper"

module NamespaceSpec
  class AbcNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
    uri "https://abc.com"
    prefix_default "abc"
  end

  class NestedChild < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "NestedChild"

      map_element :name, to: :name
    end
  end

  class Child < Lutaml::Model::Serializable
    attribute :nested_child, NestedChild

    xml do
      element "NestedChild"

      map_element :NestedChild, to: :nested_child
    end
  end

  class Parent < Lutaml::Model::Serializable
    attribute :child, Child

    xml do
      element "Parent"
      namespace AbcNamespace

      map_element :Child, to: :child
    end
  end
end

RSpec.describe "XML Namespace Handling" do
  # Ensure adapter is always reset after each example to prevent pollution
  after(:each) do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  describe "basic namespace inheritance" do
    let(:parsed) { NamespaceSpec::Parent.from_xml(xml) }
    let(:xml) do
      <<~XML
        <Parent xmlns="https://abc.com">
          <Child>
            <NestedChild>
              <name>Rogger moore</name>
            </NestedChild>
          </Child>
        </Parent>
      XML
    end

    it "parses nested child using root namespace" do
      expect(parsed.child.nested_child.name).to eq("Rogger moore")
    end

    it "round-trips xml" do
      expect(parsed.to_xml).to be_xml_equivalent_to(xml)
    end
  end

  shared_examples "namespace inheritance behavior" do
    describe "native type elements" do
      it "inherit parent namespace prefix" do
        ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
          uri "http://example.com/test"
          prefix_default "test"
        end

        model = Class.new(Lutaml::Model::Serializable) do
          attribute :description, :string
          attribute :name, :string

          xml do
            namespace ns
            element "Element"
            map_element "description", to: :description
            map_element "name", to: :name
          end
        end

        instance = model.new(description: "text", name: "value")
        xml = instance.to_xml(prefix: true)

        # Elements without explicit namespace are in blank namespace
        expected_xml = <<~XML
          <test:Element xmlns:test="http://example.com/test">
            <description>text</description>
            <name>value</name>
          </test:Element>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    describe "collection elements" do
      it "preserve parent namespace prefix in wrapper models" do
        ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
          uri "http://example.com/test"
          prefix_default "test"
        end

        child = Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string
          attribute :value, :string

          xml do
            namespace ns
            element "Child"
            map_attribute "id", to: :id
            map_element "value", to: :value
          end
        end

        wrapper = Class.new(Lutaml::Model::Serializable) do
          attribute :items, child, collection: true

          xml do
            namespace ns
            element "Wrapper"
            map_element "Child", to: :items
          end
        end

        parent = Class.new(Lutaml::Model::Serializable) do
          attribute :data, wrapper

          xml do
            namespace ns
            element "Parent"
            map_element "Wrapper", to: :data
          end
        end

        instance = parent.new(
          data: wrapper.new(
            items: [
              child.new(id: "1", value: "first"),
              child.new(id: "2", value: "second")
            ]
          )
        )

        xml = instance.to_xml(prefix: true)
        # value element has no namespace declaration, so it's in blank namespace
        expected_xml = <<~XML
          <test:Parent xmlns:test="http://example.com/test">
            <test:Wrapper>
              <test:Child id="1">
                <value>first</value>
              </test:Child>
              <test:Child id="2">
                <value>second</value>
              </test:Child>
            </test:Wrapper>
          </test:Parent>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "preserve namespace prefix through deep nesting" do
        ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
          uri "http://example.com/test"
          prefix_default "test"
        end

        leaf = Class.new(Lutaml::Model::Serializable) do
          attribute :text, :string

          xml do
            namespace ns
            element "Leaf"
            map_element "text", to: :text
          end
        end

        middle = Class.new(Lutaml::Model::Serializable) do
          attribute :leaves, leaf, collection: true

          xml do
            namespace ns
            element "Middle"
            map_element "Leaf", to: :leaves
          end
        end

        root_model = Class.new(Lutaml::Model::Serializable) do
          attribute :middles, middle, collection: true

          xml do
            namespace ns
            element "Root"
            map_element "Middle", to: :middles
          end
        end

        instance = root_model.new(
          middles: [
            middle.new(leaves: [leaf.new(text: "a"), leaf.new(text: "b")]),
            middle.new(leaves: [leaf.new(text: "c")])
          ]
        )

        xml = instance.to_xml(prefix: true)

        # text element has no namespace declaration, so blank namespace
        expected_xml = <<~XML
          <test:Root xmlns:test="http://example.com/test">
            <test:Middle>
              <test:Leaf>
                <text>a</text>
              </test:Leaf>
              <test:Leaf>
                <text>b</text>
              </test:Leaf>
            </test:Middle>
            <test:Middle>
              <test:Leaf>
                <text>c</text>
              </test:Leaf>
            </test:Middle>
          </test:Root>
        XML

        expect(xml).to be_xml_equivalent_to(expected_xml)
      end
    end
  end

  describe "Edge Cases: Repeated Model Types with Namespaces" do
    it "handles same model type repeated in collections with namespace inheritance" do
      ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/items"
        prefix_default "item"
      end

      item = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        attribute :value, :string

        xml do
          namespace ns
          element "Item"
          map_attribute "id", to: :id
          map_element "value", to: :value
        end
      end

      # Wrapper with collection of same type - tests plan caching
      wrapper = Class.new(Lutaml::Model::Serializable) do
        attribute :items, item, collection: true

        xml do
          namespace ns
          element "Wrapper"
          map_element "Item", to: :items
        end
      end

      instance = wrapper.new(
        items: [
          item.new(id: "1", value: "first"),
          item.new(id: "2", value: "second"),
          item.new(id: "3", value: "third")
        ]
      )

      xml = instance.to_xml(prefix: true)

      # value element has no namespace declaration, so blank namespace
      expected_xml = <<~XML
        <item:Wrapper xmlns:item="http://example.com/items">
          <item:Item id="1">
            <value>first</value>
          </item:Item>
          <item:Item id="2">
            <value>second</value>
          </item:Item>
          <item:Item id="3">
            <value>third</value>
          </item:Item>
        </item:Wrapper>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end

    it "handles nested collections with repeated types" do
      ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/nested"
        prefix_default "nst"
      end

      leaf = Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          namespace ns
          element "Leaf"
          map_element "text", to: :text
        end
      end

      branch = Class.new(Lutaml::Model::Serializable) do
        attribute :leaves, leaf, collection: true

        xml do
          namespace ns
          element "Branch"
          map_element "Leaf", to: :leaves
        end
      end

      tree = Class.new(Lutaml::Model::Serializable) do
        attribute :branches, branch, collection: true

        xml do
          namespace ns
          element "Tree"
          map_element "Branch", to: :branches
        end
      end

      instance = tree.new(
        branches: [
          branch.new(leaves: [
            leaf.new(text: "a"),
            leaf.new(text: "b")
          ]),
          branch.new(leaves: [
            leaf.new(text: "c"),
            leaf.new(text: "d")
          ])
        ]
      )

      xml = instance.to_xml(prefix: true)

      # text element has no namespace declaration, so blank namespace
      expected_xml = <<~XML
        <nst:Tree xmlns:nst="http://example.com/nested">
          <nst:Branch>
            <nst:Leaf>
              <text>a</text>
            </nst:Leaf>
            <nst:Leaf>
              <text>b</text>
            </nst:Leaf>
          </nst:Branch>
          <nst:Branch>
            <nst:Leaf>
              <text>c</text>
            </nst:Leaf>
            <nst:Leaf>
              <text>d</text>
            </nst:Leaf>
          </nst:Branch>
        </nst:Tree>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end
  end

  describe "Edge Cases: Polymorphic Collections with Namespaces" do
    it "maintains namespace consistency across polymorphic types" do
      animal_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/animals"
        prefix_default "anim"
        element_form_default :qualified
      end

      base = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :type_discriminator, :string, polymorphic_class: true

        xml do
          namespace animal_ns
          element "Animal"
          map_element "name", to: :name
          map_attribute "type", to: :type_discriminator,
            polymorphic_map: { "dog" => "Dog", "cat" => "Cat" }
        end
      end

      dog = Class.new(base) do
        attribute :breed, :string

        xml do
          namespace animal_ns
          element "Animal"
          map_element "breed", to: :breed
        end
      end

      cat = Class.new(base) do
        attribute :color, :string

        xml do
          namespace animal_ns
          element "Animal"
          map_element "color", to: :color
        end
      end

      stub_const("Dog", dog)
      stub_const("Cat", cat)

      zoo = Class.new(Lutaml::Model::Serializable) do
        attribute :animals, base, collection: true, polymorphic: [dog, cat]

        xml do
          namespace animal_ns
          element "Zoo"
          map_element "Animal", to: :animals
        end
      end

      instance = zoo.new(
        animals: [
          dog.new(name: "Buddy", type_discriminator: "dog", breed: "Labrador"),
          cat.new(name: "Whiskers", type_discriminator: "cat", color: "Orange")
        ]
      )

      xml = instance.to_xml(prefix: true)

      # Root elements should have namespace prefix
      # Subclass attributes inherit from root Animal mapping (no explicit
      # namespace inheritance)

      expected_xml = <<~XML
        <anim:Zoo xmlns:anim="http://example.com/animals">
          <anim:Animal type="dog">
            <anim:name>Buddy</anim:name>
            <anim:breed>Labrador</anim:breed>
          </anim:Animal>
          <anim:Animal type="cat">
            <anim:name>Whiskers</anim:name>
            <anim:color>Orange</anim:color>
          </anim:Animal>
        </anim:Zoo>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end
  end

  describe "Edge Cases: Mixed Namespace Scenarios" do
    it "handles elements with different namespace types in single model" do

      model_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/model"
        prefix_default "mdl"
      end

      type_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/types"
        prefix_default "typ"
      end

      attr_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/attrs"
        prefix_default "attr"
      end

      custom_type = Class.new(Lutaml::Model::Type::String) do
        xml_namespace type_ns
      end

      model = Class.new(Lutaml::Model::Serializable) do
        attribute :regular, :string
        attribute :typed, custom_type
        attribute :explicit, :string

        xml do
          namespace model_ns
          element "Mixed"

          map_element "regular", to: :regular  # Uses model namespace
          map_element "typed", to: :typed      # Uses type namespace
          map_element "explicit", to: :explicit,
            namespace: attr_ns                 # Uses explicit namespace
        end
      end

      instance = model.new(
        regular: "model-ns",
        typed: "type-ns",
        explicit: "attr-ns"
      )

      # Prefix true means the local element uses prefix form, it has no bearing
      # on whether child elements use prefix form.
      xml = instance.to_xml(prefix: true)

      # Model namespace for root (mdl prefix)
      # regular element has no explicit namespace - blank namespace (no prefix)
      # Type namespace hoisted to root (typ prefix) - used by typed element
      # Explicit namespace declared locally on explicit element (attr prefix)
      expected_xml = <<~XML
        <mdl:Mixed xmlns:mdl="http://example.com/model" xmlns:typ="http://example.com/types">
          <regular>model-ns</regular>
          <typ:typed>type-ns</typ:typed>
          <attr:explicit xmlns:attr="http://example.com/attrs">attr-ns</attr:explicit>
        </mdl:Mixed>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end

    it "handles namespace_scope with mixed declaration modes" do

      main_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/main"
        prefix_default "main"
      end

      used_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/used"
        prefix_default "used"
      end

      unused_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/unused"
        prefix_default "unused"
      end

      used_type = Class.new(Lutaml::Model::Type::String) do
        xml_namespace used_ns
      end

      model = Class.new(Lutaml::Model::Serializable) do
        attribute :data, used_type

        xml do
          namespace main_ns
          element "Document"

          # Force unused namespace to always be declared
          # Note: Type namespaces (used_ns) still declared locally unless in scope
          namespace_scope [
            { namespace: unused_ns, declare: :always }
          ]

          map_element "data", to: :data
        end
      end

      instance = model.new(data: "test-value")
      xml = instance.to_xml(prefix: true)

      expected_xml = <<~XML
        <main:Document xmlns:main="http://example.com/main" xmlns:unused="http://example.com/unused">
          <used:data xmlns:used="http://example.com/used">test-value</used:data>
        </main:Document>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end

    it "handles nested models with conflicting namespace declarations" do
      ns_a = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/a"
        prefix_default "a"
      end

      ns_b = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/b"
        prefix_default "b"
      end

      # Same prefix but different URIs
      ns_conflict = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/conflict"
        prefix_default "a"  # Conflicts with ns_a
      end

      inner = Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          namespace ns_conflict
          element "Inner"
          map_element "value", to: :value
        end
      end

      middle = Class.new(Lutaml::Model::Serializable) do
        attribute :inner, inner

        xml do
          namespace ns_b
          element "Middle"
          map_element "Inner", to: :inner
        end
      end

      outer = Class.new(Lutaml::Model::Serializable) do
        attribute :middle, middle

        xml do
          namespace ns_a
          element "Outer"
          map_element "Middle", to: :middle
        end
      end

      instance = outer.new(
        middle: middle.new(
          inner: inner.new(value: "test")
        )
      )

      xml = instance.to_xml(prefix: true)

      # CORRECT BEHAVIOR:
      # - Outer uses ns_a with prefix "a" (prefix: true applies to root)
      # - Middle uses ns_b, default format (child models use their own namespace's default presentation)
      # - Inner uses ns_conflict, default format
      # - value element has no namespace, so blank namespace (needs xmlns="" to opt out of parent's default)
      expected_xml = <<~XML
        <a:Outer xmlns:a="http://example.com/a">
          <Middle xmlns="http://example.com/b">
            <Inner xmlns="http://example.com/conflict">
              <value xmlns="">test</value>
            </Inner>
          </Middle>
        </a:Outer>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)

      parsed = outer.from_xml(xml)
      expect(parsed.middle.inner.value).to eq("test")
    end
  end

  describe "with Nokogiri adapter" do
    around do |example|
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
      example.run
    end

    after(:all) do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it_behaves_like "namespace inheritance behavior"
  end

  describe "with Ox adapter" do
    around do |example|
      Lutaml::Model::Config.xml_adapter_type = :ox
      example.run
    end

    after(:all) do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it_behaves_like "namespace inheritance behavior"
  end

  describe "with Oga adapter" do
    around do |example|
      Lutaml::Model::Config.xml_adapter_type = :oga
      example.run
    end

    after(:all) do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it_behaves_like "namespace inheritance behavior"
  end
end
