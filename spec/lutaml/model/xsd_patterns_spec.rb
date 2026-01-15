# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema"

RSpec.describe "XSD Three Pattern Architecture" do
  describe "Pattern 1: Anonymous Inline ComplexType" do
    it "generates inline complexType when only element declared" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :value, :integer

        xml do
          element "product"  # Only element, no type_name
          map_element "name", to: :name
          map_element "value", to: :value
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      # Should generate inline complexType
      expect(xsd).to include('<element name="product">')
      expect(xsd).to include('<complexType>')
      expect(xsd).not_to include('<complexType name=')
      expect(xsd).to include('<element name="name" type="xs:string"/>')
      expect(xsd).to include('<element name="value" type="xs:integer"/>')
    end

    it "generates inline complexType for nested model without type_name" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        attribute :description, :string

        xml do
          element "item"
          map_attribute "id", to: :id
          map_element "description", to: :description
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      expect(xsd).to include('<element name="item">')
      expect(xsd).to include('<complexType>')
      expect(xsd).not_to match(/<complexType name=/)
      expect(xsd).to include('<attribute name="id" type="xs:string"/>')
    end
  end

  describe "Pattern 2: Named Reusable ComplexType (Type-Only)" do
    it "generates named complexType when only type_name declared" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :value, :integer

        xml do
          type_name "ProductType"  # Only type, no element
          map_element "name", to: :name
          map_element "value", to: :value
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      # Should generate named complexType only (no element)
      expect(xsd).to include('<complexType name="ProductType">')
      expect(xsd).to include('<element name="name" type="xs:string"/>')
      expect(xsd).to include('<element name="value" type="xs:integer"/>')
      # Should NOT generate standalone element declaration
      expect(xsd).not_to match(/<element name="product"/)
    end

    it "type-only model can be referenced by other elements" do
      # Define a type-only model
      address_type = Class.new(Lutaml::Model::Serializable) do
        attribute :street, :string
        attribute :city, :string

        xml do
          type_name "AddressType"
          map_element "street", to: :street
          map_element "city", to: :city
        end
      end

      # Use it in another model
      person_klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :address, address_type

        xml do
          element "person"
          map_element "name", to: :name
          map_element "address", to: :address
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(person_klass)

      # Should reference AddressType
      expect(xsd).to include('<element name="address" type="AddressType"/>')
      expect(xsd).to include('<complexType name="AddressType">')
    end
  end

  describe "Pattern 3: Element with Named ComplexType" do
    it "generates both element and named complexType" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :value, :integer

        xml do
          element "product"
          type_name "ProductType"
          map_element "name", to: :name
          map_element "value", to: :value
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      # Should generate both element and named type
      expect(xsd).to include('<element name="product" type="ProductType"/>')
      expect(xsd).to include('<complexType name="ProductType">')
      expect(xsd).to include('<element name="name" type="xs:string"/>')
      expect(xsd).to include('<element name="value" type="xs:integer"/>')
    end

    it "allows reuse of named type by other elements" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :code, :string

        xml do
          element "catalog"
          type_name "CatalogType"  # Named type can be referenced
          map_element "name", to: :name
          map_element "code", to: :code
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      # Element references the named type
      expect(xsd).to include('<element name="catalog" type="CatalogType"/>')
      # Type definition exists separately
      expect(xsd).to include('<complexType name="CatalogType">')
    end
  end

  describe "xsd_type and type_name equivalence" do
    it "xsd_type is an alias for type_name" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          xsd_type "TestType"  # Using xsd_type (alias)
          map_element "name", to: :name
        end
      end

      mapping = klass.mappings_for(:xml)
      expect(mapping.type_name_value).to eq("TestType")
      expect(mapping.xsd_type).to eq("TestType")
      expect(mapping.xsd_type).to eq(mapping.type_name)
    end

    it "type_name and xsd_type produce identical results" do
      klass1 = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "test"
          type_name "TestType"
          map_element "name", to: :name
        end
      end

      klass2 = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "test"
          xsd_type "TestType"  # Same using alias
          map_element "name", to: :name
        end
      end

      xsd1 = Lutaml::Model::Schema.to_xsd(klass1)
      xsd2 = Lutaml::Model::Schema.to_xsd(klass2)

      # Both should generate identical XSD
      expect(xsd1).to eq(xsd2)
      expect(xsd1).to include('<element name="test" type="TestType"/>')
      expect(xsd1).to include('<complexType name="TestType">')
    end

    it "xsd_type does NOT auto-set no_root (NO MAGIC)" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          xsd_type "TestType"  # Does NOT imply type-only
          map_element "name", to: :name
        end
      end

      mapping = klass.mappings_for(:xml)
      # NO MAGIC: xsd_type doesn't set @no_root
      expect(mapping.no_root?).to be_falsy
      # Type name is still set
      expect(mapping.type_name_value).to eq("TestType")
    end
  end

  describe "pattern selection decision tree" do
    it "Pattern 1: element only -> anonymous inline" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string
        xml do
          element "simple"
          map_element "value", to: :value
        end
      end

      mapping = klass.mappings_for(:xml)
      expect(mapping.element_name).to eq("simple")
      expect(mapping.type_name_value).to be_nil
      expect(mapping.no_root?).to be_falsy

      xsd = Lutaml::Model::Schema.to_xsd(klass)
      expect(xsd).to include('<element name="simple">')
      expect(xsd).not_to match(/<element name="simple" type=/)
    end

    it "Pattern 2: type_name only -> named reusable" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string
        xml do
          type_name "SimpleType"  # No element
          map_element "value", to: :value
        end
      end

      mapping = klass.mappings_for(:xml)
      expect(mapping.element_name).to be_nil
      expect(mapping.type_name_value).to eq("SimpleType")

      xsd = Lutaml::Model::Schema.to_xsd(klass)
      expect(xsd).to include('<complexType name="SimpleType">')
      # Should not have standalone element declaration (only child elements in sequence are OK)
      expect(xsd).not_to match(/<element name="SimpleType"/)
    end

    it "Pattern 3: both -> element with named type" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string
        xml do
          element "simple"
          type_name "SimpleType"
          map_element "value", to: :value
        end
      end

      mapping = klass.mappings_for(:xml)
      expect(mapping.element_name).to eq("simple")
      expect(mapping.type_name_value).to eq("SimpleType")

      xsd = Lutaml::Model::Schema.to_xsd(klass)
      expect(xsd).to include('<element name="simple" type="SimpleType"/>')
      expect(xsd).to include('<complexType name="SimpleType">')
    end
  end
end
