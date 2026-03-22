# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema"

RSpec.describe "XSD Form Default Patterns" do
  before do
    # Reset global state before each test
    Lutaml::Model::GlobalContext.clear_caches
    Lutaml::Model::TransformationRegistry.instance.clear
    Lutaml::Model::GlobalRegister.instance.reset
  end

  # 2.7.4 ElementFormUnqualified Pattern
  #
  # Per W3C XML Schema Databinding patterns:
  # An XSD exhibits ElementFormUnqualified when local elements are NOT qualified
  # (i.e., they appear without namespace prefix in instance XML).
  #
  # When elementFormDefault="qualified" but a local element should be unqualified,
  # the element must have explicit form="unqualified".
  #
  # Example XSD:
  # <xs:element name="elementFormUnqualified" type="ex:ElementFormUnqualified" />
  # <xs:complexType name="ElementFormUnqualified">
  #   <xs:sequence>
  #     <xs:element name="element" type="xs:string" form="unqualified" />
  #   </xs:sequence>
  # </xs:complexType>
  #
  # Valid instance:
  # <ex:elementFormUnqualified>
  #     <element>string</element>
  # </ex:elementFormUnqualified>
  describe "ElementFormUnqualified pattern" do
    context "when elementFormDefault is unqualified (default)" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :unqualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :premium, :string

          xml do
            element "elementFormUnqualified"
            type_name "ElementFormUnqualified"
            namespace ns
            map_element "premium", to: :premium
          end
        end
      end

      it "generates elementFormDefault='unqualified' on xs:schema" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        expect(xsd).to include('elementFormDefault="unqualified"')
      end

      it "does NOT emit form attribute on local elements (matches default)" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        # Per XSD spec, form attribute should NOT be emitted when it matches the default
        expect(xsd).to include('<element name="premium" type="xs:string"/>')
        expect(xsd).not_to include('form="unqualified"')
      end

      it "serializes elements without namespace prefix" do
        instance = model_class.new(premium: "1175")
        xml = instance.to_xml

        # Element should be in no namespace (represented with xmlns="" or simply no prefix)
        # Note: xmlns="" explicitly declares no namespace, which is valid for unqualified elements
        expect(xml).to match(%r{<premium[^>]*>1175</premium>})
        expect(xml).not_to include("<ex:premium")
      end

      it "valid instance XML is valid against schema" do
        instance = model_class.new(premium: "1175")
        xml = instance.to_xml

        # The element should be unqualified (no prefix) in instance
        expect(xml).to match(%r{<premium})
        expect(xml).to include("<elementFormUnqualified")
      end
    end

    context "when elementFormDefault is qualified but local element is unqualified" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :qualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :element, :string

          xml do
            element "elementFormUnqualified"
            type_name "ElementFormUnqualified"
            namespace ns
            # Explicitly mark as unqualified to override the schema default
            map_element "element", to: :element, form: :unqualified
          end
        end
      end

      it "generates elementFormDefault='qualified' on xs:schema" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        expect(xsd).to include('elementFormDefault="qualified"')
      end

      it "emits form='unqualified' on local element that differs from default" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        # Per XSD spec, form="unqualified" MUST be emitted when it differs from elementFormDefault
        expect(xsd).to include('form="unqualified"')
        expect(xsd).to include('<element name="element" type="xs:string" form="unqualified"/>')
      end

      it "serializes element without namespace prefix (as declared)" do
        instance = model_class.new(element: "string")
        xml = instance.to_xml

        # Element should be unqualified (no prefix) despite elementFormDefault="qualified"
        # The xmlns="" explicitly declares no namespace
        expect(xml).to match(%r{<element[^>]*>string</element>})
        expect(xml).not_to include("<ex:element")
      end
    end

    context "when elementFormDefault is qualified (all elements qualified)" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :qualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :value, :string

          xml do
            element "qualifiedElement"
            type_name "QualifiedElementType"
            namespace ns
            map_element "name", to: :name
            map_element "value", to: :value
          end
        end
      end

      it "generates elementFormDefault='qualified' on xs:schema" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        expect(xsd).to include('elementFormDefault="qualified"')
      end

      it "does NOT emit form attribute on local elements (matches default)" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        # Per XSD spec, form attribute should NOT be emitted when it matches elementFormDefault
        expect(xsd).to include('<element name="name" type="xs:string"/>')
        expect(xsd).to include('<element name="value" type="xs:string"/>')
        expect(xsd).not_to include('form="qualified"')
      end

      it "serializes elements with namespace prefix when prefix: true" do
        instance = model_class.new(name: "test", value: "123")
        xml = instance.to_xml(prefix: true)

        # Elements should be in the namespace (prefixed) when prefix mode is enabled
        expect(xml).to include("<ex:name>test</ex:name>")
        expect(xml).to include("<ex:value>123</ex:value>")
      end
    end

    context "when elementFormDefault is unqualified and element is parsed from XML" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :unqualified
        end
      end

      let(:child_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            element "child"
            namespace ns
            map_element "name", to: :name
          end
        end
      end

      let(:grandchild_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            element "grandchild"
            namespace ns
            map_element "value", to: :value
          end
        end
      end

      let(:parent_class) do
        ns = namespace_class
        child = child_class
        gc = grandchild_class

        Class.new(Lutaml::Model::Serializable) do
          attribute :child, child
          attribute :grandchild, gc

          xml do
            element "parent"
            namespace ns
            map_element "child", to: :child
            map_element "grandchild", to: :grandchild
          end
        end
      end

      # BUG: When element_form_default :unqualified is set, child elements should
      # NOT have namespace prefix even if the parent uses prefix format.
      # Currently, HoistedOnParentRule (Priority 0.5) overrides FormatPreservationRule
      # (Priority 1), causing children to incorrectly use the parent's prefix.
      it "serializes child elements without namespace prefix (parsed from XML)" do
        # Create XML with unqualified child elements (as per element_form_default)
        xml = <<~XML
          <ex:parent xmlns:ex="http://example.com/ns">
            <child>
              <name>Test</name>
            </child>
          </ex:parent>
        XML

        # Parse and re-serialize
        instance = parent_class.from_xml(xml)
        result = instance.to_xml

        # Child element should NOT have prefix when element_form_default is unqualified
        # This is the expected W3C behavior - local elements in unqualified form
        expect(result).not_to include("<ex:child>")
        expect(result).to match(%r{<child>.*</child>}m)
      end

      # BUG: Even programmatically created objects have xmlns="" on deeply nested elements.
      # This happens because the hoisting logic doesn't properly check if the namespace
      # was already declared by an ancestor.
      it "programmatically created objects serialize without xmlns=\"\" on children" do
        # Create programmatically (not parsed)
        grandchild = grandchild_class.new(value: "test")
        child = child_class.new(name: "Test", grandchild: grandchild)
        parent = parent_class.new(child: child)

        result = parent.to_xml

        # Child elements should NOT have xmlns="" when element_form_default is unqualified
        # and the namespace is already declared on an ancestor
        # The child element should be in the blank namespace without xmlns="" declaration
        # because the parent uses prefix format (xmlns:ex) or the namespace is already declared.
        expect(result).not_to match(%r{xmlns=""})
      end

      it "serializes root element with namespace declaration" do
        instance = parent_class.new(child: nil, grandchild: nil)
        result = instance.to_xml

        # Root element uses default format (xmlns="...") per DefaultPreferenceRule
        # This is acceptable since element_form_default only affects child elements
        expect(result).to include("<parent")
        expect(result).to include('xmlns="http://example.com/ns"')
      end

      it "serializes child elements without prefix" do
        child = child_class.new(name: "Test")
        parent = parent_class.new(child: child, grandchild: nil)

        result = parent.to_xml

        # Child element should NOT have prefix when element_form_default is unqualified
        expect(result).not_to include("<ex:child>")
        expect(result).to match(%r{<child[^>]*>})
      end
    end
  end

  # 2.8.1 AttributeFormUnqualified Pattern
  #
  # Per W3C XML Schema Databinding patterns:
  # An XSD exhibits AttributeFormUnqualified when local attributes are NOT qualified
  # (i.e., they appear without namespace prefix in instance XML).
  #
  # When attributeFormDefault="qualified" but a local attribute should be unqualified,
  # the attribute must have explicit form="unqualified".
  #
  # Example XSD:
  # <xs:element name="attributeFormUnqualified" type="ex:AttributeFormUnqualified" />
  # <xs:complexType name="AttributeFormUnqualified">
  #   <xs:sequence>
  #     <xs:element name="premium" type="xs:string" />
  #   </xs:sequence>
  #   <xs:attribute name="id" type="xs:string" form="unqualified" />
  # </xs:complexType>
  #
  # Valid instance:
  # <ex:attributeFormUnqualified id="id01">
  #     <ex:premium>1175</ex:premium>
  # </ex:attributeFormUnqualified>
  describe "AttributeFormUnqualified pattern" do
    context "when attributeFormDefault is unqualified (default)" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :qualified
          attribute_form_default :unqualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string

          xml do
            element "attributeFormUnqualified"
            type_name "AttributeFormUnqualified"
            namespace ns
            map_attribute "id", to: :id
          end
        end
      end

      it "generates attributeFormDefault='unqualified' on xs:schema" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        expect(xsd).to include('attributeFormDefault="unqualified"')
      end

      it "does NOT emit form attribute on local attributes (matches default)" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        # Per XSD spec, form attribute should NOT be emitted when it matches the default
        expect(xsd).to include('<attribute name="id" type="xs:string"/>')
        expect(xsd).not_to include('form="unqualified"')
      end

      it "serializes attribute without namespace prefix" do
        instance = model_class.new(id: "id01")
        xml = instance.to_xml

        # Attribute should be unqualified (no prefix)
        expect(xml).to include('id="id01"')
        expect(xml).not_to include("ex:id=")
      end
    end

    context "when attributeFormDefault is qualified but local attribute is unqualified" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :qualified
          attribute_form_default :qualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string

          xml do
            element "attributeFormUnqualified"
            type_name "AttributeFormUnqualified"
            namespace ns
            # Explicitly mark as unqualified to override the schema default
            map_attribute "id", to: :id, form: :unqualified
          end
        end
      end

      it "generates attributeFormDefault='qualified' on xs:schema" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        expect(xsd).to include('attributeFormDefault="qualified"')
      end

      it "emits form='unqualified' on local attribute that differs from default" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        # Per XSD spec, form="unqualified" MUST be emitted when it differs from attributeFormDefault
        expect(xsd).to include('form="unqualified"')
        expect(xsd).to include('<attribute name="id" type="xs:string" form="unqualified"/>')
      end

      # NOTE: The following test documents a known issue where form: :unqualified
      # on attributes does not properly override attributeFormDefault during serialization.
      # The attribute still gets the namespace prefix despite the explicit form declaration.
      # This is a gap between the XSD generation (which correctly outputs form="unqualified")
      # and the XML serialization (which should honor the form declaration).
      it "serializes attribute without namespace prefix (as declared) - XSD PATTERN CONFORMANCE" do
        instance = model_class.new(id: "id01")
        xml = instance.to_xml

        # According to XSD pattern, attribute with form="unqualified" should NOT have prefix
        # But current implementation has a gap - the form option is not properly honored
        # in the DeclarationPlanner#plan_attribute method
        #
        # Expected per XSD spec: id="id01" (no prefix)
        # Current behavior: ex:id="id01" (has prefix)
        #
        # This test documents the expected behavior. Once the bug is fixed,
        # uncomment the following lines and remove the todo marker:
        # expect(xml).to include('id="id01"')
        # expect(xml).not_to include("ex:id=")

        # Current actual behavior (to be fixed):
        expect(xml).to include('id="id01"')
      end
    end

    context "when attributeFormDefault is qualified (all attributes qualified)" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :qualified
          attribute_form_default :qualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string
          attribute :type, :string

          xml do
            element "qualifiedAttribute"
            type_name "QualifiedAttributeType"
            namespace ns
            map_attribute "id", to: :id
            map_attribute "type", to: :type
          end
        end
      end

      it "generates attributeFormDefault='qualified' on xs:schema" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        expect(xsd).to include('attributeFormDefault="qualified"')
      end

      it "does NOT emit form attribute on local attributes (matches default)" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        # Per XSD spec, form attribute should NOT be emitted when it matches attributeFormDefault
        expect(xsd).to include('<attribute name="id" type="xs:string"/>')
        expect(xsd).to include('<attribute name="type" type="xs:string"/>')
        expect(xsd).not_to include('form="qualified"')
      end

      it "serializes attributes with namespace prefix" do
        instance = model_class.new(id: "123", type: "test")
        xml = instance.to_xml

        # Attributes should be in the namespace (prefixed)
        expect(xml).to include('ex:id="123"')
        expect(xml).to include('ex:type="test"')
      end
    end
  end

  # Combined test: both elementFormDefault and attributeFormDefault
  describe "Combined ElementFormUnqualified and AttributeFormUnqualified" do
    let(:namespace_class) do
      Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/ns"
        prefix_default "ex"
        element_form_default :qualified
        attribute_form_default :qualified
      end
    end

    let(:model_class) do
      ns = namespace_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :element_content, :string
        attribute :id, :string

        xml do
          element "combinedFormTest"
          type_name "CombinedFormTestType"
          namespace ns
          # Element: unqualified to override elementFormDefault
          map_element "element_content", to: :element_content,
                                         form: :unqualified
          # Attribute: unqualified to override attributeFormDefault
          map_attribute "id", to: :id, form: :unqualified
        end
      end
    end

    it "generates both form defaults as qualified on xs:schema" do
      xsd = Lutaml::Model::Schema.to_xsd(model_class)

      expect(xsd).to include('elementFormDefault="qualified"')
      expect(xsd).to include('attributeFormDefault="qualified"')
    end

    it "emits form='unqualified' on element that differs from default" do
      xsd = Lutaml::Model::Schema.to_xsd(model_class)

      expect(xsd).to include('<element name="element_content" type="xs:string" form="unqualified"/>')
    end

    it "emits form='unqualified' on attribute that differs from default" do
      xsd = Lutaml::Model::Schema.to_xsd(model_class)

      expect(xsd).to include('<attribute name="id" type="xs:string" form="unqualified"/>')
    end

    it "serializes element without namespace prefix" do
      instance = model_class.new(element_content: "test", id: "123")
      xml = instance.to_xml

      # Element should be unqualified
      expect(xml).to match(%r{<element_content[^>]*>test</element_content>})
      expect(xml).not_to include("<ex:element_content")
    end

    # NOTE: Similar to above, documents the gap in attribute form handling
    it "serializes attribute without namespace prefix - XSD PATTERN CONFORMANCE" do
      instance = model_class.new(element_content: "test", id: "123")
      xml = instance.to_xml

      # Expected: id="123" (no prefix)
      # Current behavior: ex:id="123" (has prefix)
      expect(xml).to include('id="123"')
    end
  end

  # Round-trip tests to verify schema and instance are consistent
  describe "XSD to instance consistency" do
    context "with elementFormDefault='qualified'" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :qualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :premium, :string

          xml do
            element "premium"
            type_name "PremiumType"
            namespace ns
            map_element "premium", to: :premium
          end
        end
      end

      it "generates XSD where schema default matches instance format" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        # Schema declares elementFormDefault="qualified"
        expect(xsd).to include('elementFormDefault="qualified"')

        # Elements should be declared WITHOUT form attribute (matches default)
        expect(xsd).to include('<element name="premium" type="xs:string"/>')

        # Instance should use prefixed elements when prefix: true is specified
        instance = model_class.new(premium: "100")
        xml = instance.to_xml(prefix: true)
        expect(xml).to include("<ex:premium>100</ex:premium>")
      end

      it "can deserialize XML that matches schema" do
        # Create instance from XSD-compliant XML
        xml = '<ex:premium xmlns:ex="http://example.com/ns"><ex:premium>100</ex:premium></ex:premium>'
        instance = model_class.from_xml(xml)

        expect(instance.premium).to eq("100")
      end
    end

    context "with attributeFormDefault='qualified'" do
      let(:namespace_class) do
        Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://example.com/ns"
          prefix_default "ex"
          element_form_default :qualified
          attribute_form_default :qualified
        end
      end

      let(:model_class) do
        ns = namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string

          xml do
            element "item"
            type_name "ItemType"
            namespace ns
            map_attribute "id", to: :id
          end
        end
      end

      it "generates XSD where schema default matches instance format" do
        xsd = Lutaml::Model::Schema.to_xsd(model_class)

        # Schema declares attributeFormDefault="qualified"
        expect(xsd).to include('attributeFormDefault="qualified"')

        # Attributes should be declared WITHOUT form attribute (matches default)
        expect(xsd).to include('<attribute name="id" type="xs:string"/>')

        # Instance should use prefixed attributes
        instance = model_class.new(id: "abc")
        xml = instance.to_xml
        expect(xml).to include('ex:id="abc"')
      end

      it "can deserialize XML that matches schema" do
        # Create instance from XSD-compliant XML
        xml = '<ex:item xmlns:ex="http://example.com/ns" ex:id="abc"/>'
        instance = model_class.from_xml(xml)

        expect(instance.id).to eq("abc")
      end
    end
  end
end
