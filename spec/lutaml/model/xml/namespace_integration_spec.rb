# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML Namespace Integration" do
  # Define test namespaces
  let(:contact_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "https://example.com/schemas/contact/v1"
      schema_location "https://example.com/schemas/contact/v1/contact.xsd"
      prefix_default "contact"
      element_form_default :qualified
      version "1.0"
      documentation "Contact information schema"
    end
  end

  let(:address_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "https://example.com/schemas/address/v1"
      schema_location "https://example.com/schemas/address/v1/address.xsd"
      prefix_default "addr"
    end
  end

  describe "using XmlNamespace classes in mappings" do
    let(:person_class) do
      ns = contact_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :email, :string

        xml do
          element "person"
          namespace ns
          sequence do
            map_element "name", to: :name
            map_element "email", to: :email
          end
        end
      end
    end

    it "resolves namespace from class" do
      mapping = person_class.mappings_for(:xml)
      expect(mapping.namespace_uri).to eq("https://example.com/schemas/contact/v1")
      expect(mapping.namespace_prefix).to eq("contact")
      expect(mapping.namespace_class).to eq(contact_namespace)
    end

    it "uses element declaration" do
      mapping = person_class.mappings_for(:xml)
      expect(mapping.element_name).to eq("person")
      expect(mapping.root_element).to eq("person")
      expect(mapping.root?).to be true
    end

    it "serializes with namespace" do
      person = person_class.new(name: "John Doe", email: "john@example.com")
      xml = person.to_xml

      # NEW: Default behavior uses default namespace (xmlns="...")
      expect(xml).to include('xmlns="https://example.com/schemas/contact/v1"')
      expect(xml).to include("<person")
      # Child elements are unqualified (local elements)
      expect(xml).to include("<name>John Doe</name>")
      expect(xml).to include("<email>john@example.com</email>")
    end

    it "serializes with prefix when prefix: true option used" do
      person = person_class.new(name: "John Doe", email: "john@example.com")
      xml = person.to_xml(prefix: true)

      # With prefix: true, root uses prefix
      expect(xml).to include('xmlns:contact="https://example.com/schemas/contact/v1"')
      expect(xml).to include("<contact:person")
      # Child elements remain unqualified (element_form_default not fully implemented yet)
      expect(xml).to include("<name>John Doe</name>")
      expect(xml).to include("<email>john@example.com</email>")
    end
  end

  describe "mixed_content as separate method" do
    let(:paragraph_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :bold_text, :string, collection: true
        attribute :italic_text, :string, collection: true

        xml do
          element "p"
          mixed_content # New explicit method
          map_element "bold", to: :bold_text
          map_element "i", to: :italic_text
        end
      end
    end

    it "enables mixed content flag" do
      mapping = paragraph_class.mappings_for(:xml)
      expect(mapping.mixed_content?).to be true
      expect(mapping.ordered?).to be true
    end
  end

  describe "backward compatibility with string namespaces" do
    let(:legacy_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          root "legacy", mixed: true
          namespace "https://example.com/legacy", "leg"
          map_element "value", to: :value
        end
      end
    end

    it "still works with string URI and prefix" do
      mapping = legacy_class.mappings_for(:xml)
      expect(mapping.namespace_uri).to eq("https://example.com/legacy")
      expect(mapping.namespace_prefix).to eq("leg")
      expect(mapping.mixed_content?).to be true
    end

    it "serializes correctly" do
      instance = legacy_class.new(value: "test")
      xml = instance.to_xml

      # NEW: Default behavior uses default namespace
      expect(xml).to include('xmlns="https://example.com/legacy"')
      expect(xml).to include("<legacy")
      expect(xml).to include("<value>test</value>")
    end

    it "serializes with prefix when prefix: true used" do
      instance = legacy_class.new(value: "test")
      xml = instance.to_xml(prefix: true)

      # With prefix: true on root, but child elements stay unqualified
      # (no element_form_default :qualified set)
      expect(xml).to include('xmlns:leg="https://example.com/legacy"')
      expect(xml).to include("<leg:legacy")
      expect(xml).to include("<value>test</value>")  # Child unqualified
    end
  end

  describe "validation of namespace parameters" do
    it "validates correctly with proper parameters" do
      # This should work without errors
      klass = Class.new(Lutaml::Model::Serializable) do
        xml do
          root "test"
          namespace "https://example.com", "prefix"
        end
      end

      mapping = klass.mappings_for(:xml)
      expect(mapping.namespace_uri).to eq("https://example.com")
      expect(mapping.namespace_prefix).to eq("prefix")
    end

    it "raises error for invalid namespace class" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          xml do
            root "test"
            namespace String
          end
        end
      end.to raise_error(ArgumentError, /XmlNamespace class/)
    end
  end

  describe "no_root deprecation" do
    it "shows deprecation warning" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          xml do
            no_root
            map_element "value", to: :value
          end
        end
      end.to output(/DEPRECATED: no_root is deprecated/).to_stderr
    end

    it "still works for backward compatibility" do
      klass = nil
      expect do
        klass = Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string
          xml do
            no_root
            map_element "value", to: :value
          end
        end
      end.to output(/DEPRECATED/).to_stderr

      mapping = klass.mappings_for(:xml)
      expect(mapping.no_root?).to be true
    end
  end

  describe "type-only models (no element declaration)" do
    let(:address_type_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :street, :string
        attribute :city, :string

        xml do
          # No element declaration - type-only model
          no_root # Explicitly mark as no root
          sequence do
            map_element "street", to: :street
            map_element "city", to: :city
          end
        end
      end
    end

    let(:person_with_address_class) do
      addr_class = address_type_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :address, addr_class

        xml do
          element "person"
          sequence do
            map_element "name", to: :name
            map_element "address", to: :address
          end
        end
      end
    end

    it "cannot be serialized standalone when marked no_root" do
      address = nil
      expect do
        address = address_type_class.new(street: "123 Main St", city: "Boston")
      end.to output(/DEPRECATED/).to_stderr

      expect do
        address.to_xml
      end.to raise_error(Lutaml::Model::NoRootMappingError)
    end

    it "can be used as embedded type" do
      expect do
        person = person_with_address_class.new(
          name: "Jane",
          address: address_type_class.new(street: "123 Main St",
                                          city: "Boston"),
        )
        xml = person.to_xml

        expect(xml).to include("<person")
        expect(xml).to include("<name>Jane</name>")
        expect(xml).to include("<address")
        expect(xml).to include("<street>123 Main St</street>")
        expect(xml).to include("<city>Boston</city>")
      end.to output(/DEPRECATED/).to_stderr
    end
  end

  describe "documentation support" do
    let(:documented_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string

        xml do
          element "document"
          documentation "A test document structure"
          map_element "title", to: :title
        end
      end
    end

    it "stores documentation in mapping" do
      mapping = documented_class.mappings_for(:xml)
      expect(mapping.documentation_text).to eq("A test document structure")
    end
  end

  describe "type_name support" do
    let(:custom_type_name_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "item"
          type_name "CustomItemType"
          map_element "value", to: :value
        end
      end
    end

    it "stores custom type name" do
      mapping = custom_type_name_class.mappings_for(:xml)
      expect(mapping.type_name).to eq("CustomItemType")
    end
  end
end
