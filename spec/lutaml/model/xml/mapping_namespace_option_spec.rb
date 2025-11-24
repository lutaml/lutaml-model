require "spec_helper"
require "lutaml/model"

RSpec.describe "Xml::Mapping namespace option formats" do
  # Define test namespaces
  let(:test_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/test"
      prefix_default "test"
    end
  end

  let(:override_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/override"
      prefix_default "override"
    end
  end

  let(:xsi_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://www.w3.org/2001/XMLSchema-instance"
      prefix_default "xsi"
    end
  end

  describe "map_element namespace option" do
    context "with XmlNamespace class (current syntax)" do
      let(:model_class) do
        ns = test_namespace
        Class.new do
          include Lutaml::Model::Serialize

          attribute :value, :string

          xml do
            root "document"
            map_element "value", to: :value, namespace: ns
          end

          def self.name
            "TestModel"
          end
        end
      end

      it "applies namespace from class" do
        instance = model_class.new(value: "test content")
        xml = instance.to_xml

        expect(xml).to include("<test:value>test content</test:value>")
      end

      it "includes namespace declaration in XML" do
        instance = model_class.new(value: "test content")
        xml = instance.to_xml

        expect(xml).to include('xmlns:test="http://example.com/test"')
      end

      it "works in round-trip" do
        original = model_class.new(value: "round trip test")
        xml = original.to_xml
        parsed = model_class.from_xml(xml)

        expect(parsed.value).to eq("round trip test")
        expect(parsed).to eq(original)
      end

      it "stores namespace_class in mapping rule" do
        mapping = model_class.mappings_for(:xml)
        element_rule = mapping.find_element(:value)

        expect(element_rule.namespace_class).to eq(test_namespace)
        expect(element_rule.namespace).to eq("http://example.com/test")
        expect(element_rule.prefix).to eq("test")
      end
    end

    context "with URI string (deprecated backward compat)" do
      let(:model_class) do
        Class.new do
          include Lutaml::Model::Serialize

          attribute :value, :string

          xml do
            root "document"
            map_element "value", to: :value,
                                 namespace: "http://example.com/test",
                                 prefix: "test"
          end

          def self.name
            "TestModel"
          end
        end
      end

      it "creates anonymous XmlNamespace from URI" do
        mapping = model_class.mappings_for(:xml)
        element_rule = mapping.find_element(:value)

        expect(element_rule.namespace_class).not_to be_nil
        expect(element_rule.namespace_class).to be < Lutaml::Model::XmlNamespace
        expect(element_rule.namespace).to eq("http://example.com/test")
        expect(element_rule.prefix).to eq("test")
      end

      it "applies namespace from string" do
        instance = model_class.new(value: "test content")
        xml = instance.to_xml

        expect(xml).to include("<test:value>test content</test:value>")
      end

      it "includes namespace declaration" do
        instance = model_class.new(value: "test content")
        xml = instance.to_xml

        expect(xml).to include('xmlns:test="http://example.com/test"')
      end

      it "works in round-trip" do
        original = model_class.new(value: "backward compat test")
        xml = original.to_xml
        parsed = model_class.from_xml(xml)

        expect(parsed.value).to eq("backward compat test")
        expect(parsed).to eq(original)
      end
    end

    context "with URI string without prefix" do
      let(:model_class) do
        Class.new do
          include Lutaml::Model::Serialize

          attribute :value, :string

          xml do
            root "document"
            map_element "value", to: :value,
                                 namespace: "http://example.com/test"
          end

          def self.name
            "TestModel"
          end
        end
      end

      it "creates anonymous XmlNamespace without prefix" do
        mapping = model_class.mappings_for(:xml)
        element_rule = mapping.find_element(:value)

        expect(element_rule.namespace_class).not_to be_nil
        expect(element_rule.namespace).to eq("http://example.com/test")
        expect(element_rule.prefix).to be_nil
      end
    end

    context "with :inherit symbol" do
      let(:parent_namespace) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/parent"
          prefix_default "parent"
        end
      end

      let(:model_class) do
        parent_ns = parent_namespace
        Class.new do
          include Lutaml::Model::Serialize

          attribute :inherited, :string

          xml do
            root "document"
            namespace parent_ns
            map_element "inherited", to: :inherited, namespace: :inherit
          end

          def self.name
            "TestModel"
          end
        end
      end

      it "inherits parent namespace" do
        instance = model_class.new(inherited: "test value")
        xml = instance.to_xml(prefix: true)

        # Element should use parent namespace
        expect(xml).to include("<parent:inherited>test value</parent:inherited>")
        expect(xml).to include('xmlns:parent="http://example.com/parent"')
      end

      it "normalizes :inherit to nil in namespace_class" do
        mapping = model_class.mappings_for(:xml)
        element_rule = mapping.find_element(:inherited)

        # :inherit is normalized to nil during initialization
        expect(element_rule.namespace_class).to be_nil
        expect(element_rule.namespace).to be_nil
        # The :inherit behavior is handled during resolution, not storage
      end
    end

    context "with nil (no namespace)" do
      let(:model_class) do
        Class.new do
          include Lutaml::Model::Serialize

          attribute :value, :string

          xml do
            root "document"
            map_element "value", to: :value
          end

          def self.name
            "TestModel"
          end
        end
      end

      it "creates unqualified element" do
        instance = model_class.new(value: "test content")
        xml = instance.to_xml

        expect(xml).to include("<value>test content</value>")
        expect(xml).not_to match(/<\w+:value/)
      end

      it "stores nil namespace" do
        mapping = model_class.mappings_for(:xml)
        element_rule = mapping.find_element(:value)

        expect(element_rule.namespace_class).to be_nil
        expect(element_rule.namespace).to be_nil
        expect(element_rule.prefix).to be_nil
      end
    end
  end

  describe "map_attribute namespace option" do
    context "with XmlNamespace class" do
      let(:model_class) do
        xsi_ns = xsi_namespace
        Class.new do
          include Lutaml::Model::Serialize

          attribute :type, :string

          xml do
            root "document"
            map_attribute "type", to: :type, namespace: xsi_ns
          end

          def self.name
            "TestModel"
          end
        end
      end

      it "applies namespace to attribute" do
        instance = model_class.new(type: "TestType")
        xml = instance.to_xml

        expect(xml).to include('xsi:type="TestType"')
      end

      it "includes namespace declaration" do
        instance = model_class.new(type: "TestType")
        xml = instance.to_xml

        expect(xml).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      end

      it "stores namespace_class in mapping rule" do
        mapping = model_class.mappings_for(:xml)
        attr_rule = mapping.find_attribute(:type)

        expect(attr_rule.namespace_class).to eq(xsi_namespace)
        expect(attr_rule.namespace).to eq("http://www.w3.org/2001/XMLSchema-instance")
        expect(attr_rule.prefix).to eq("xsi")
      end
    end

    context "with URI string (backward compat)" do
      let(:model_class) do
        Class.new do
          include Lutaml::Model::Serialize

          attribute :type, :string

          xml do
            root "document"
            map_attribute "type", to: :type,
                                  namespace: "http://www.w3.org/2001/XMLSchema-instance",
                                  prefix: "xsi"
          end

          def self.name
            "TestModel"
          end
        end
      end

      it "creates anonymous XmlNamespace from URI" do
        mapping = model_class.mappings_for(:xml)
        attr_rule = mapping.find_attribute(:type)

        expect(attr_rule.namespace_class).not_to be_nil
        expect(attr_rule.namespace_class).to be < Lutaml::Model::XmlNamespace
        expect(attr_rule.namespace).to eq("http://www.w3.org/2001/XMLSchema-instance")
        expect(attr_rule.prefix).to eq("xsi")
      end

      it "applies namespace from string" do
        instance = model_class.new(type: "TestType")
        xml = instance.to_xml

        expect(xml).to include('xsi:type="TestType"')
      end
    end

    context "unprefixed (W3C default)" do
      let(:model_class) do
        Class.new do
          include Lutaml::Model::Serialize

          attribute :id, :string

          xml do
            root "document"
            map_attribute "id", to: :id
          end

          def self.name
            "TestModel"
          end
        end
      end

      it "creates unqualified attribute" do
        instance = model_class.new(id: "test123")
        xml = instance.to_xml

        expect(xml).to include('id="test123"')
        expect(xml).not_to match(/\w+:id=/)
      end

      it "follows W3C rule: unprefixed attributes have no namespace" do
        mapping = model_class.mappings_for(:xml)
        attr_rule = mapping.find_attribute(:id)

        expect(attr_rule.namespace_class).to be_nil
        expect(attr_rule.namespace).to be_nil
        expect(attr_rule.prefix).to be_nil
      end
    end
  end

  describe "namespace normalization" do
    let(:model_class) do
      ns = test_namespace
      Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :string

        xml do
          root "document"
          map_element "value", to: :value, namespace: ns
        end

        def self.name
          "TestModel"
        end
      end
    end

    it "normalizes XmlNamespace class to internal format" do
      mapping = model_class.mappings_for(:xml)
      element_rule = mapping.find_element(:value)

      # Should store the class and extract uri/prefix
      expect(element_rule.namespace_class).to eq(test_namespace)
      expect(element_rule.namespace).to eq("http://example.com/test")
      expect(element_rule.prefix).to eq("test")
    end

    it "normalizes URI string to XmlNamespace class" do
      model_with_string = Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :string

        xml do
          root "document"
          map_element "value", to: :value,
                               namespace: "http://example.com/string-test",
                               prefix: "str"
        end

        def self.name
          "StringModel"
        end
      end

      mapping = model_with_string.mappings_for(:xml)
      element_rule = mapping.find_element(:value)

      # Should create anonymous XmlNamespace class
      expect(element_rule.namespace_class).to be_a(Class)
      expect(element_rule.namespace_class).to be < Lutaml::Model::XmlNamespace
      expect(element_rule.namespace_class.uri).to eq("http://example.com/string-test")
      expect(element_rule.namespace_class.prefix_default).to eq("str")
    end

    it "handles :inherit symbol correctly" do
      parent_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/inherit-test"
        prefix_default "inherit"
      end

      model_with_inherit = Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :string
        pns = parent_ns

        xml do
          root "document"
          namespace pns
          map_element "value", to: :value, namespace: :inherit
        end

        def self.name
          "InheritModel"
        end
      end

      mapping = model_with_inherit.mappings_for(:xml)
      element_rule = mapping.find_element(:value)

      # :inherit is normalized to nil during storage
      # The inheritance happens during resolution at render time
      expect(element_rule.namespace_class).to be_nil
      expect(element_rule.namespace).to be_nil
    end
  end

  describe "mixed namespace scenarios" do
    context "both elements and attributes with namespaces" do
      let(:model_class) do
        test_ns = test_namespace
        xsi_ns = xsi_namespace

        Class.new do
          include Lutaml::Model::Serialize

          attribute :field, :string
          attribute :attr, :string

          xml do
            root "document"
            map_element "field", to: :field, namespace: test_ns
            map_attribute "attr", to: :attr, namespace: xsi_ns
          end

          def self.name
            "MixedModel"
          end
        end
      end

      it "both get correct namespaces applied" do
        instance = model_class.new(field: "field value", attr: "attr value")
        xml = instance.to_xml

        expect(xml).to include("<test:field>field value</test:field>")
        expect(xml).to include('xsi:attr="attr value"')
        expect(xml).to include('xmlns:test="http://example.com/test"')
        expect(xml).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      end
    end

    context "explicit namespace overrides type namespace" do
      let(:type_namespace) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/type-level"
          prefix_default "type"
        end
      end

      let(:model_class) do
        type_ns = type_namespace
        override_ns = override_namespace

        typed_string = Class.new(Lutaml::Model::Type::String)
        typed_string.xml_namespace(type_ns)

        Class.new do
          include Lutaml::Model::Serialize

          attribute :field, typed_string

          xml do
            root "document"
            # Explicit namespace should override type namespace
            map_element "field", to: :field, namespace: override_ns
          end

          def self.name
            "OverrideModel"
          end
        end
      end

      it "explicit namespace takes priority over type namespace" do
        instance = model_class.new(field: "test value")
        xml = instance.to_xml

        # Should use override namespace, not type namespace
        expect(xml).to include("<override:field>test value</override:field>")
        expect(xml).to include('xmlns:override="http://example.com/override"')
        expect(xml).not_to include("type:field")
        expect(xml).not_to include('xmlns:type="http://example.com/type-level"')
      end
    end
  end

  describe "round-trip for all namespace formats" do
    it "XmlNamespace class format round-trips correctly" do
      model_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :string
        ns = Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/roundtrip"
          prefix_default "rt"
        end

        xml do
          root "document"
          map_element "value", to: :value, namespace: ns
        end

        def self.name
          "RoundTripClass"
        end
      end

      original = model_class.new(value: "class format")
      xml = original.to_xml
      parsed = model_class.from_xml(xml)

      expect(parsed.value).to eq("class format")
      expect(parsed).to eq(original)
    end

    it "URI string format round-trips correctly" do
      model_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :string

        xml do
          root "document"
          map_element "value", to: :value,
                               namespace: "http://example.com/roundtrip",
                               prefix: "rt"
        end

        def self.name
          "RoundTripString"
        end
      end

      original = model_class.new(value: "string format")
      xml = original.to_xml
      parsed = model_class.from_xml(xml)

      expect(parsed.value).to eq("string format")
      expect(parsed).to eq(original)
    end

    it ":inherit format serializes correctly" do
      parent_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/parent-roundtrip"
        prefix_default "parent"
      end

      model_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :string
        pns = parent_ns

        xml do
          root "document"
          namespace pns
          map_element "value", to: :value, namespace: :inherit
        end

        def self.name
          "RoundTripInherit"
        end
      end

      original = model_class.new(value: "inherit format")
      xml = original.to_xml

      # Serialization works - element inherits parent namespace
      expect(xml).to include("<parent:value>inherit format</parent:value>")
      expect(xml).to include('xmlns:parent="http://example.com/parent-roundtrip"')

      # Note: Full round-trip deserialization has limitations with :inherit
      # The element is serialized with inherited namespace prefix,
      # but deserialization requires explicit namespace mapping
    end
  end
end
