# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

RSpec.describe Lutaml::Model::Xml::Transformation do
  describe "rule compilation" do
    it "compiles element mappings into rules" do
      class SimpleModel < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :value, :integer

        xml do
          root "SimpleModel"
          map_element "name", to: :name
          map_element "value", to: :value
        end
      end

      transformation = SimpleModel.transformation_for(:xml)

      expect(transformation).to be_a(Lutaml::Model::Xml::Transformation)
      expect(transformation.compiled_rules.length).to eq(2)

      name_rule = transformation.compiled_rules.find { |r| r.attribute_name == :name }
      expect(name_rule.serialized_name).to eq("name")
      expect(name_rule.option(:mapping_type)).to eq(:element)
    end

    it "compiles attribute mappings into rules" do
      class ModelWithAttrs < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :type, :string

        xml do
          root "Model"
          map_attribute "id", to: :id
          map_attribute "type", to: :type
        end
      end

      transformation = ModelWithAttrs.transformation_for(:xml)

      expect(transformation.compiled_rules.length).to eq(2)

      id_rule = transformation.compiled_rules.find { |r| r.attribute_name == :id }
      expect(id_rule.option(:mapping_type)).to eq(:attribute)
    end

    it "compiles content mappings into rules" do
      class ModelWithContent < Lutaml::Model::Serializable
        attribute :text, :string

        xml do
          root "Model"
          map_content to: :text
        end
      end

      transformation = ModelWithContent.transformation_for(:xml)

      expect(transformation.compiled_rules.length).to eq(1)

      content_rule = transformation.compiled_rules.first
      expect(content_rule.attribute_name).to eq(:text)
      expect(content_rule.option(:mapping_type)).to eq(:content)
      expect(content_rule.serialized_name).to be_nil
    end
  end

  describe "simple transformation" do
    it "transforms a simple model to XmlElement tree" do
      class SimpleContact < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :email, :string

        xml do
          root "Contact"
          map_element "name", to: :name
          map_element "email", to: :email
        end
      end

      contact = SimpleContact.new(name: "John Doe", email: "john@example.com")
      transformation = SimpleContact.transformation_for(:xml)

      xml_element = transformation.transform(contact)

      expect(xml_element).to be_a(Lutaml::Model::XmlDataModel::XmlElement)
      expect(xml_element.name).to eq("Contact")
      expect(xml_element.children.length).to eq(2)

      name_child = xml_element.children.find { |c| c.is_a?(Lutaml::Model::XmlDataModel::XmlElement) && c.name == "name" }
      expect(name_child.text_content).to eq("John Doe")
    end

    it "handles attributes correctly" do
      class PersonWithId < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :name, :string

        xml do
          root "Person"
          map_attribute "id", to: :id
          map_element "name", to: :name
        end
      end

      person = PersonWithId.new(id: "123", name: "Jane")
      transformation = PersonWithId.transformation_for(:xml)

      xml_element = transformation.transform(person)

      expect(xml_element.attributes.length).to eq(1)
      expect(xml_element.attributes.first.name).to eq("id")
      expect(xml_element.attributes.first.value).to eq("123")

      expect(xml_element.children.length).to eq(1)
      expect(xml_element.children.first.name).to eq("name")
    end

    it "handles text content correctly" do
      class Note < Lutaml::Model::Serializable
        attribute :content, :string

        xml do
          root "Note"
          map_content to: :content
        end
      end

      note = Note.new(content: "Hello World")
      transformation = Note.transformation_for(:xml)

      xml_element = transformation.transform(note)

      expect(xml_element.text_content).to eq("Hello World")
      expect(xml_element.children).to be_empty
    end
  end

  describe "nested model transformation" do
    it "transforms nested models recursively" do
      class Address < Lutaml::Model::Serializable
        attribute :street, :string
        attribute :city, :string

        xml do
          root "Address"
          map_element "street", to: :street
          map_element "city", to: :city
        end
      end

      class PersonWithAddress < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :address, Address

        xml do
          root "Person"
          map_element "name", to: :name
          map_element "Address", to: :address
        end
      end

      address = Address.new(street: "123 Main St", city: "Springfield")
      person = PersonWithAddress.new(name: "John", address: address)

      transformation = PersonWithAddress.transformation_for(:xml)
      xml_element = transformation.transform(person)

      expect(xml_element.name).to eq("Person")
      expect(xml_element.children.length).to eq(2)

      address_child = xml_element.children.find { |c| c.is_a?(Lutaml::Model::XmlDataModel::XmlElement) && c.name == "Address" }
      expect(address_child).not_to be_nil
      expect(address_child.children.length).to eq(2)

      street = address_child.children.find { |c| c.name == "street" }
      expect(street.text_content).to eq("123 Main St")
    end

    it "pre-compiles child transformations" do
      class Book < Lutaml::Model::Serializable
        attribute :title, :string
        xml do
          root "Book"
          map_element "title", to: :title
        end
      end

      class Library < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :book, Book

        xml do
          root "Library"
          map_element "name", to: :name
          map_element "Book", to: :book
        end
      end

      transformation = Library.transformation_for(:xml)
      book_rule = transformation.compiled_rules.find { |r| r.attribute_name == :book }

      expect(book_rule.nested_model?).to be true
      expect(book_rule.child_transformation).to be_a(Lutaml::Model::Xml::Transformation)
      expect(book_rule.child_transformation.model_class).to eq(Book)
    end
  end

  describe "collection transformation" do
    it "transforms collections of simple values" do
      class TagList < Lutaml::Model::Serializable
        attribute :tags, :string, collection: true

        xml do
          root "TagList"
          map_element "tag", to: :tags
        end
      end

      tag_list = TagList.new(tags: ["ruby", "xml", "test"])
      transformation = TagList.transformation_for(:xml)

      xml_element = transformation.transform(tag_list)

      expect(xml_element.children.length).to eq(3)
      expect(xml_element.children.all? { |c| c.name == "tag" }).to be true

      texts = xml_element.children.map(&:text_content)
      expect(texts).to eq(["ruby", "xml", "test"])
    end

    it "transforms collections of nested models" do
      class Item < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :price, :float

        xml do
          root "Item"
          map_element "name", to: :name
          map_element "price", to: :price
        end
      end

      class Cart < Lutaml::Model::Serializable
        attribute :items, Item, collection: true

        xml do
          root "Cart"
          map_element "Item", to: :items
        end
      end

      items = [
        Item.new(name: "Book", price: 9.99),
        Item.new(name: "Pen", price: 1.99)
      ]
      cart = Cart.new(items: items)

      transformation = Cart.transformation_for(:xml)
      xml_element = transformation.transform(cart)

      expect(xml_element.children.length).to eq(2)
      expect(xml_element.children.all? { |c| c.name == "Item" }).to be true

      first_item = xml_element.children.first
      name_elem = first_item.children.find { |c| c.name == "name" }
      expect(name_elem.text_content).to eq("Book")
    end
  end

  describe "namespace handling" do
    it "attaches namespace classes to elements" do
      module TestNs
        class MyNamespace < Lutaml::Model::Xml::Namespace
          uri "http://example.com/test"
          prefix_default "test"
        end
      end

      class NamespacedModel < Lutaml::Model::Serializable
        attribute :value, :string

        xml do
          root "Model"
          namespace TestNs::MyNamespace
          map_element "value", to: :value
        end
      end

      model = NamespacedModel.new(value: "test")
      transformation = NamespacedModel.transformation_for(:xml)

      xml_element = transformation.transform(model)

      expect(xml_element.namespace_class).to eq(TestNs::MyNamespace)
    end

    it "collects all namespaces without traversing types" do
      module NsTest
        class Ns1 < Lutaml::Model::Xml::Namespace
          uri "http://example.com/ns1"
          prefix_default "ns1"
        end

        class Ns2 < Lutaml::Model::Xml::Namespace
          uri "http://example.com/ns2"
          prefix_default "ns2"
        end
      end

      class Child < Lutaml::Model::Serializable
        attribute :value, :string
        xml do
          root "Child"
          namespace NsTest::Ns2
          map_element "value", to: :value
        end
      end

      class Parent < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :child, Child

        xml do
          root "Parent"
          namespace NsTest::Ns1
          map_element "name", to: :name
          map_element "Child", to: :child
        end
      end

      transformation = Parent.transformation_for(:xml)
      namespaces = transformation.all_namespaces

      expect(namespaces).to include(NsTest::Ns1)
      expect(namespaces).to include(NsTest::Ns2)
    end
  end

  describe "value transformation" do
    it "applies export transformations" do
      class TransformedModel < Lutaml::Model::Serializable
        attribute :name, :string, transform: {
          export: ->(v) { v.upcase }
        }

        xml do
          root "Model"
          map_element "name", to: :name
        end
      end

      model = TransformedModel.new(name: "test")
      transformation = TransformedModel.transformation_for(:xml)

      xml_element = transformation.transform(model)

      name_elem = xml_element.children.first
      expect(name_elem.text_content).to eq("TEST")
    end
  end

  describe "render options" do
    it "skips default values when render_default is false" do
      class ModelWithDefault < Lutaml::Model::Serializable
        attribute :status, :string, default: -> { "active" }

        xml do
          root "Model"
          map_element "status", to: :status, render_default: false
        end
      end

      model = ModelWithDefault.new
      transformation = ModelWithDefault.transformation_for(:xml)

      xml_element = transformation.transform(model)

      expect(xml_element.children).to be_empty
    end

    it "renders nil values when render_nil is true" do
      class ModelWithNil < Lutaml::Model::Serializable
        attribute :optional, :string

        xml do
          root "Model"
          map_element "optional", to: :optional, render_nil: true
        end
      end

      model = ModelWithNil.new(optional: nil)
      transformation = ModelWithNil.transformation_for(:xml)

      xml_element = transformation.transform(model)

      # Note: The actual nil rendering (xsi:nil) will be handled by adapters
      # Here we just verify the element is created
      expect(xml_element.children.length).to eq(1)
    end
  end

  describe "caching" do
    it "caches transformations per format and register" do
      class CachedModel < Lutaml::Model::Serializable
        attribute :value, :string
        xml do
          root "Model"
          map_element "value", to: :value
        end
      end

      t1 = CachedModel.transformation_for(:xml)
      t2 = CachedModel.transformation_for(:xml)

      expect(t1.object_id).to eq(t2.object_id)
    end
  end
end