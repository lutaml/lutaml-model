require "spec_helper"

module NamespaceSpec
  class NestedChild < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      root "NestedChild"

      map_element :name, to: :name
    end
  end

  class Child < Lutaml::Model::Serializable
    attribute :nested_child, NestedChild

    xml do
      root "NestedChild"

      map_element :NestedChild, to: :nested_child
    end
  end

  class Parent < Lutaml::Model::Serializable
    attribute :child, Child

    xml do
      root "Parent"
      namespace "https://abc.com"

      map_element :Child, to: :child
    end
  end
end

RSpec.describe "XML Namespace Handling" do
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
        ns = Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/test"
          prefix_default "test"
        end

        model = Class.new(Lutaml::Model::Serializable) do
          attribute :description, :string
          attribute :name, :string

          xml do
            namespace ns
            root "Element"
            map_element "description", to: :description
            map_element "name", to: :name
          end
        end

        instance = model.new(description: "text", name: "value")
        xml = instance.to_xml(prefix: true)

        expect(xml).to include('<test:Element')
        expect(xml).to include('<test:description>text</test:description>')
        expect(xml).to include('<test:name>value</test:name>')
      end
    end

    describe "collection elements" do
      it "preserve parent namespace prefix in wrapper models" do
        ns = Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/test"
          prefix_default "test"
        end

        child = Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string
          attribute :value, :string

          xml do
            namespace ns
            root "Child"
            map_attribute "id", to: :id
            map_element "value", to: :value
          end
        end

        wrapper = Class.new(Lutaml::Model::Serializable) do
          attribute :items, child, collection: true

          xml do
            namespace ns
            root "Wrapper"
            map_element "Child", to: :items
          end
        end

        parent = Class.new(Lutaml::Model::Serializable) do
          attribute :data, wrapper

          xml do
            namespace ns
            root "Parent"
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

        expect(xml).to include('<test:Parent')
        expect(xml).to include('<test:Wrapper>')
        expect(xml).to include('<test:Child id="1">')
        expect(xml).to include('<test:value>first</test:value>')
        expect(xml).to include('<test:Child id="2">')
        expect(xml).to include('<test:value>second</test:value>')
      end

      it "preserve namespace prefix through deep nesting" do
        ns = Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/test"
          prefix_default "test"
        end

        leaf = Class.new(Lutaml::Model::Serializable) do
          attribute :text, :string

          xml do
            namespace ns
            root "Leaf"
            map_element "text", to: :text
          end
        end

        middle = Class.new(Lutaml::Model::Serializable) do
          attribute :leaves, leaf, collection: true

          xml do
            namespace ns
            root "Middle"
            map_element "Leaf", to: :leaves
          end
        end

        root_model = Class.new(Lutaml::Model::Serializable) do
          attribute :middles, middle, collection: true

          xml do
            namespace ns
            root "Root"
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

        expect(xml).to include('<test:Root')
        expect(xml).to include('<test:Middle>')
        expect(xml).to include('<test:Leaf>')
        expect(xml).to include('<test:text>a</test:text>')
        expect(xml).to include('<test:text>b</test:text>')
        expect(xml).to include('<test:text>c</test:text>')
      end
    end
  end

  describe "with Nokogiri adapter" do
    around do |example|
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
      example.run
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it_behaves_like "namespace inheritance behavior"
  end

  describe "with Ox adapter" do
    around do |example|
      Lutaml::Model::Config.xml_adapter_type = :ox
      example.run
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it_behaves_like "namespace inheritance behavior"
  end

  describe "with Oga adapter" do
    around do |example|
      Lutaml::Model::Config.xml_adapter_type = :oga
      example.run
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it_behaves_like "namespace inheritance behavior"
  end
end
