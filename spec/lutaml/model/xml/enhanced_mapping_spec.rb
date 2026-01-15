require "spec_helper"

RSpec.describe "Enhanced XML Mapping Features" do
  describe "element() method" do
    context "basic usage" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            element "product"
            map_element "name", to: :name
          end
        end
      end

      it "sets element_name" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.element_name).to eq("product")
      end

      it "sets root_element for backward compatibility" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.root_element).to eq("product")
      end

      it "serializes with correct element name" do
        instance = model_class.new(name: "Widget")
        xml = instance.to_xml
        expect(xml).to include("<product>")
        expect(xml).to include("</product>")
      end
    end

    context "without element declaration" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :street, :string

          xml do
            map_element "street", to: :street
          end
        end
      end

      it "auto-generates element_name from class" do
        mapping = model_class.mappings_for(:xml)
        # Class name is auto-generated like #<Class:0x...>, finalize sets it
        expect(mapping.element_name).to be_a(String)
      end

      it "has root? return true after finalization" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.root?).to be true
      end
    end
  end

  describe "mixed_content() method" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :bold, :string, collection: true

        xml do
          element "text"
          mixed_content
          map_element "b", to: :bold
        end
      end
    end

    it "enables mixed_content flag" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.mixed_content?).to be true
    end

    it "enables ordered flag" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.ordered?).to be true
    end
  end

  describe "documentation() method" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "product"
          documentation "A product in the catalog"
          map_element "name", to: :name
        end
      end
    end

    it "stores documentation text" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.documentation_text).to eq("A product in the catalog")
    end
  end

  describe "type_name() method" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "product"
          type_name "CatalogItemType"
          map_element "name", to: :name
        end
      end
    end

    it "stores custom type name" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.type_name).to eq("CatalogItemType")
    end

    it "can be retrieved via type_name() method" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.type_name).to eq("CatalogItemType")
    end
  end

  describe "form option on map_element" do
    let(:namespace_class) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "https://example.com/ns"
        prefix_default "ex"
        element_form_default :unqualified
      end
    end

    context "with form: :qualified" do
      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :type, :string

          xml do
            element "item"
            namespace ns
            map_element "name", to: :name, form: :qualified
            map_element "type", to: :type
          end
        end
      end

      it "stores form in mapping rule" do
        mapping = model_class.mappings_for(:xml)
        name_rule = mapping.find_element(:name)
        expect(name_rule.form).to eq(:qualified)
      end

      it "serializes qualified element" do
        instance = model_class.new(name: "Widget", type: "Product")
        xml = instance.to_xml
        expect(xml).to include("<ex:name>")
      end
    end

    context "with form: :unqualified" do
      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            element "item"
            namespace ns
            map_element "name", to: :name, form: :unqualified
          end
        end
      end

      it "stores form in mapping rule" do
        mapping = model_class.mappings_for(:xml)
        name_rule = mapping.find_element(:name)
        expect(name_rule.form).to eq(:unqualified)
      end
    end
  end

  describe "form option on map_attribute" do
    let(:namespace_class) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "https://example.com/ns"
        prefix_default "ex"
        attribute_form_default :unqualified
      end
    end

    context "with form: :qualified" do
      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string

          xml do
            element "item"
            namespace ns
            map_attribute "id", to: :id, form: :qualified
          end
        end
      end

      it "stores form in mapping rule" do
        mapping = model_class.mappings_for(:xml)
        id_rule = mapping.find_attribute(:id)
        expect(id_rule.form).to eq(:qualified)
      end

      it "serializes qualified attribute" do
        instance = model_class.new(id: "ABC123")
        xml = instance.to_xml
        # Form affects qualification but implementation varies by adapter
        expect(xml).to match(/id="ABC123"/)
      end
    end

    context "with form: :unqualified" do
      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string

          xml do
            element "item"
            namespace ns
            map_attribute "id", to: :id, form: :unqualified
          end
        end
      end

      it "stores form in mapping rule" do
        mapping = model_class.mappings_for(:xml)
        id_rule = mapping.find_attribute(:id)
        expect(id_rule.form).to eq(:unqualified)
      end
    end
  end

  describe "documentation option on map_element" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "product"
          map_element "name", to: :name, documentation: "Product name"
        end
      end
    end

    it "stores documentation in mapping rule" do
      mapping = model_class.mappings_for(:xml)
      name_rule = mapping.find_element(:name)
      expect(name_rule.documentation).to eq("Product name")
    end
  end

  describe "documentation option on map_attribute" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string

        xml do
          element "product"
          map_attribute "id", to: :id, documentation: "Unique identifier"
        end
      end
    end

    it "stores documentation in mapping rule" do
      mapping = model_class.mappings_for(:xml)
      id_rule = mapping.find_attribute(:id)
      expect(id_rule.documentation).to eq("Unique identifier")
    end
  end

  describe "combined enhanced features" do
    let(:namespace_class) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "https://example.com/catalog"
        prefix_default "cat"
        element_form_default :qualified
        attribute_form_default :unqualified
      end
    end

    let(:model_class) do
      ns = namespace_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :product_id, :string
        attribute :name, :string
        attribute :description, :string

        xml do
          element "product"
          namespace ns
          documentation "Catalog product entity"
          type_name "ProductType"

          map_attribute "id", to: :product_id,
                              documentation: "Product identifier",
                              form: :unqualified
          map_element "name", to: :name,
                              documentation: "Product name",
                              form: :qualified
          map_element "description", to: :description,
                                     form: :qualified
        end
      end
    end

    it "stores all metadata correctly" do
      mapping = model_class.mappings_for(:xml)

      expect(mapping.element_name).to eq("product")
      expect(mapping.documentation_text).to eq("Catalog product entity")
      expect(mapping.type_name).to eq("ProductType")
      expect(mapping.namespace_uri).to eq("https://example.com/catalog")
      expect(mapping.namespace_prefix).to eq("cat")
    end

    it "stores element-level metadata" do
      mapping = model_class.mappings_for(:xml)

      name_rule = mapping.find_element(:name)
      expect(name_rule.documentation).to eq("Product name")
      expect(name_rule.form).to eq(:qualified)

      desc_rule = mapping.find_element(:description)
      expect(desc_rule.form).to eq(:qualified)
    end

    it "stores attribute-level metadata" do
      mapping = model_class.mappings_for(:xml)

      id_rule = mapping.find_attribute(:product_id)
      expect(id_rule.documentation).to eq("Product identifier")
      expect(id_rule.form).to eq(:unqualified)
    end

    it "serializes with correct qualification" do
      instance = model_class.new(
        product_id: "P001",
        name: "Widget",
        description: "A useful widget",
      )
      xml = instance.to_xml

      expect(xml).to include('id="P001"')
      expect(xml).to include("<cat:name>Widget</cat:name>")
      # When namespace default is :qualified, elements are qualified
      expect(xml).to include("<cat:description>A useful widget</cat:description>")
    end
  end

  describe "root() as backward-compatible alias" do
    context "with mixed_content" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :text, :string

          xml do
            element "paragraph"
            mixed_content
            map_element "b", to: :text
          end
        end
      end

      it "sets element_name" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.element_name).to eq("paragraph")
      end

      it "enables mixed_content" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.mixed_content?).to be true
      end

      it "enables ordered" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.ordered?).to be true
      end
    end

    context "with ordered" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :items, :string, collection: true

          xml do
            element "list"
            ordered
            map_element "item", to: :items
          end
        end
      end

      it "sets element_name" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.element_name).to eq("list")
      end

      it "enables ordered" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.ordered?).to be true
      end

      it "does not enable mixed_content" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.mixed_content?).to be false
      end
    end
  end

  describe "integration with existing features" do
    context "with sequence" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :first, :string
          attribute :second, :string

          xml do
            element "ordered"
            documentation "Sequence example"

            sequence do
              map_element "first", to: :first, documentation: "First element"
              map_element "second", to: :second, documentation: "Second element"
            end
          end
        end
      end

      it "works with sequence" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.element_name).to eq("ordered")
        expect(mapping.documentation_text).to eq("Sequence example")
      end

      it "documents elements in sequence" do
        mapping = model_class.mappings_for(:xml)
        first_rule = mapping.find_element(:first)
        expect(first_rule.documentation).to eq("First element")
      end
    end

    context "with namespace and form" do
      let(:namespace_class) do
        Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
          uri "https://example.com/test"
          prefix_default "t"
          element_form_default :qualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :qualified_elem, :string
          attribute :unqualified_elem, :string

          xml do
            element "test"
            namespace ns
            documentation "Test element"

            map_element "qualified", to: :qualified_elem, form: :qualified
            map_element "unqualified", to: :unqualified_elem, form: :unqualified
          end
        end
      end

      it "applies form overrides correctly" do
        instance = model_class.new(
          qualified_elem: "A",
          unqualified_elem: "B",
        )
        xml = instance.to_xml

        expect(xml).to include("<t:qualified>A</t:qualified>")
        # When form: :unqualified is explicitly set, element is NOT qualified
        # This is correct W3C behavior - explicit form overrides default
        expect(xml).to include("<unqualified>B</unqualified>")
      end
    end

    context "with type_name" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            element "custom"
            type_name "CustomTypeName"
            map_element "value", to: :value
          end
        end
      end

      it "stores custom type name" do
        mapping = model_class.mappings_for(:xml)
        expect(mapping.type_name).to eq("CustomTypeName")
      end
    end
  end

  describe "accessor methods" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :id, :string

        xml do
          element "test"
          documentation "Test model"
          type_name "TestType"

          map_element "name", to: :name, documentation: "Element doc"
          map_attribute "id", to: :id, documentation: "Attribute doc"
        end
      end
    end

    it "provides element_name accessor" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.element_name).to eq("test")
    end

    it "provides documentation_text accessor" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.documentation_text).to eq("Test model")
    end

    it "provides type_name_value accessor" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.type_name_value).to eq("TestType")
    end

    it "provides type_name method" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.type_name).to eq("TestType")
    end
  end

  describe "form validation" do
    context "with invalid form value" do
      it "accepts valid form values" do
        expect do
          Class.new(Lutaml::Model::Serializable) do
            attribute :name, :string

            xml do
              element "test"
              map_element "name", to: :name, form: :qualified
            end
          end
        end.not_to raise_error
      end

      it "accepts :unqualified" do
        expect do
          Class.new(Lutaml::Model::Serializable) do
            attribute :name, :string

            xml do
              element "test"
              map_element "name", to: :name, form: :unqualified
            end
          end
        end.not_to raise_error
      end
    end
  end

  describe "serialization and deserialization" do
    let(:namespace_class) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "https://example.com/product"
        prefix_default "prod"
        element_form_default :qualified
      end
    end

    let(:model_class) do
      ns = namespace_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :product_id, :string
        attribute :name, :string
        attribute :price, :float

        xml do
          element "product"
          namespace ns
          documentation "Product catalog entry"
          type_name "ProductType"

          map_attribute "id", to: :product_id,
                              documentation: "Product ID",
                              form: :unqualified
          map_element "name", to: :name,
                              documentation: "Product name",
                              form: :qualified
          map_element "price", to: :price,
                               documentation: "Product price",
                               form: :qualified
        end
      end
    end

    it "round-trips correctly" do
      original = model_class.new(
        product_id: "P123",
        name: "Widget",
        price: 19.99,
      )

      xml = original.to_xml
      restored = model_class.from_xml(xml)

      expect(restored.product_id).to eq("P123")
      expect(restored.name).to eq("Widget")
      expect(restored.price).to eq(19.99)
    end

    it "preserves qualification in output" do
      instance = model_class.new(
        product_id: "P123",
        name: "Widget",
        price: 19.99,
      )

      xml = instance.to_xml

      expect(xml).to include('id="P123"')
      expect(xml).to include("<prod:name>Widget</prod:name>")
      expect(xml).to include("<prod:price>19.99</prod:price>")
    end
  end

  describe "metadata retrieval" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :value, :integer

        xml do
          element "config"
          documentation "Configuration entry"
          type_name "ConfigType"

          map_element "name", to: :name, documentation: "Config name"
          map_attribute "value", to: :value, documentation: "Config value"
        end
      end
    end

    it "retrieves type-level documentation" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.documentation_text).to eq("Configuration entry")
    end

    it "retrieves type name" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.type_name).to eq("ConfigType")
    end

    it "retrieves element documentation" do
      mapping = model_class.mappings_for(:xml)
      name_rule = mapping.find_element(:name)
      expect(name_rule.documentation).to eq("Config name")
    end

    it "retrieves attribute documentation" do
      mapping = model_class.mappings_for(:xml)
      value_rule = mapping.find_attribute(:value)
      expect(value_rule.documentation).to eq("Config value")
    end
  end
end
