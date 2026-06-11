# frozen_string_literal: true

require "spec_helper"

RSpec.describe "validate_xml_with XSD constructs" do
  def fixture_path(name)
    File.expand_path("../../fixtures/xml/#{name}", __dir__)
  end

  describe "kitchen-sink schema (pattern, enumeration, attributes, " \
           "types, occurrence, nested complex type)" do
    before do
      path = fixture_path("validate_xml_with_product.xsd")

      stub_const("XsdDimensions", Class.new(Lutaml::Model::Serializable) do
        attribute :width, :string
        attribute :height, :string

        xml do
          element "dimensions"
          map_element "width", to: :width
          map_element "height", to: :height
        end
      end)

      stub_const("XsdProduct", Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        attribute :status, :string
        attribute :sku, :string
        attribute :price, :string
        attribute :released, :string
        attribute :tags, :string, collection: true
        attribute :note, :string
        attribute :dimensions, XsdDimensions

        xml do
          root "product"
          map_attribute "id", to: :id
          map_attribute "status", to: :status
          map_element "sku", to: :sku
          map_element "price", to: :price
          map_element "released", to: :released
          map_element "tag", to: :tags
          map_element "note", to: :note
          map_element "dimensions", to: :dimensions
        end

        validate_xml_with path
      end)
    end

    let(:valid_attributes) do
      {
        id: "p1",
        status: "published",
        sku: "ABC-1234",
        price: "9.99",
        released: "2026-06-11",
        tags: %w[a b c],
        note: "boundary case: three tags is maxOccurs",
        dimensions: XsdDimensions.new(width: "10", height: "20"),
      }
    end

    def product(**overrides)
      XsdProduct.new(valid_attributes.merge(overrides))
    end

    it "accepts a document satisfying every construct" do
      expect(product.validate).to be_empty
    end

    it "accepts a document omitting all optional parts" do
      minimal = product(status: nil, tags: [], note: nil, dimensions: nil)

      expect(minimal.validate).to be_empty
    end

    it "collects xs:pattern violations" do
      errors = product(sku: "bad-sku").validate

      expect(errors.map(&:message)).to include(a_string_including("sku"))
    end

    it "collects xs:enumeration violations" do
      errors = product(status: "archived").validate

      expect(errors.map(&:message)).to include(a_string_including("status"))
    end

    it "collects missing required attribute violations" do
      errors = product(id: nil).validate

      expect(errors.map(&:message)).to include(
        a_string_including("attribute 'id' is required"),
      )
    end

    it "collects xs:decimal lexical violations" do
      errors = product(price: "free").validate

      expect(errors.map(&:message)).to include(a_string_including("price"))
    end

    it "collects xs:date lexical violations" do
      errors = product(released: "tomorrow").validate

      expect(errors.map(&:message)).to include(a_string_including("released"))
    end

    it "collects maxOccurs violations" do
      errors = product(tags: %w[a b c d]).validate

      expect(errors.map(&:message)).to include(a_string_including("tag"))
    end

    it "collects violations inside nested complex types" do
      bad_nested = XsdDimensions.new(width: "wide", height: "20")
      errors = product(dimensions: bad_nested).validate

      expect(errors.map(&:message)).to include(a_string_including("width"))
    end
  end

  describe "multiple schema paths" do
    before do
      base = fixture_path("validate_xml_with_person.xsd")
      strict = fixture_path("validate_xml_with_person_strict.xsd")

      stub_const("XsdDualSchemaPerson",
                 Class.new(Lutaml::Model::Serializable) do
                   attribute :name, :string
                   attribute :age, :string

                   xml do
                     root "person"
                     map_element "name", to: :name
                     map_element "age", to: :age
                   end

                   validate_xml_with base, strict
                 end)
    end

    it "passes when the document conforms to every schema" do
      person = XsdDualSchemaPerson.new(name: "Alice", age: "30")

      expect(person.validate).to be_empty
    end

    it "attributes violations to the schema that rejected the document" do
      person = XsdDualSchemaPerson.new(name: "Old", age: "200")
      errors = person.validate

      expect(errors.size).to eq(1)
      expect(errors.first.schema_path).to eq(
        fixture_path("validate_xml_with_person_strict.xsd"),
      )
    end
  end

  describe "targetNamespace with qualified elements" do
    let(:schema_path) { fixture_path("validate_xml_with_address.xsd") }

    before do
      path = schema_path
      stub_const("XsdNamespacedDoc",
                 Class.new(Lutaml::Model::Serializable) do
                   attribute :city, :string

                   xml do
                     root "address"
                     map_element "city", to: :city
                   end

                   validate_xml_with path
                 end)
    end

    it "accepts a document in the target namespace" do
      xml = '<address xmlns="http://example.com/address">' \
            "<city>Berlin</city></address>"

      expect(XsdNamespacedDoc.validate_xml(xml)).to be_empty
    end

    it "rejects a document missing the target namespace" do
      xml = "<address><city>Berlin</city></address>"

      expect(XsdNamespacedDoc.validate_xml(xml)).not_to be_empty
    end
  end

  describe "xs:choice" do
    before do
      path = fixture_path("validate_xml_with_contact.xsd")
      stub_const("XsdChoiceDoc",
                 Class.new(Lutaml::Model::Serializable) do
                   attribute :email, :string

                   xml do
                     root "contact"
                     map_element "email", to: :email
                   end

                   validate_xml_with path
                 end)
    end

    it "accepts a document using exactly one branch" do
      xml = "<contact><email>a@b.c</email></contact>"

      expect(XsdChoiceDoc.validate_xml(xml)).to be_empty
    end

    it "rejects a document using both branches" do
      xml = "<contact><email>a@b.c</email><phone>123</phone></contact>"

      expect(XsdChoiceDoc.validate_xml(xml)).not_to be_empty
    end
  end
end
