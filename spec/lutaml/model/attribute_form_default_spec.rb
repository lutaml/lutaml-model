# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attribute form default behavior" do
  context "with attributeFormDefault :unqualified (W3C default)" do
    let(:namespace_class) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/ns"
        prefix_default "ex"
        element_form_default :qualified
        attribute_form_default :unqualified  # Default - attributes NOT qualified
      end
    end

    let(:model_class) do
      ns = namespace_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        attribute :value, :integer

        xml do
          element "item"
          namespace ns
          map_attribute "id", to: :id
          map_attribute "value", to: :value
        end
      end
    end

    it "serializes attributes without namespace prefix" do
      item = model_class.new(id: "123", value: 42)
      xml = item.to_xml(prefix: true)

      expect(xml).to include('<ex:item')
      expect(xml).to include('id="123"')  # No prefix
      expect(xml).to include('value="42"')  # No prefix
      expect(xml).not_to include('ex:id=')
      expect(xml).not_to include('ex:value=')
    end

    it "deserializes attributes without namespace prefix" do
      xml = '<ex:item xmlns:ex="http://example.com/ns" id="123" value="42"/>'
      item = model_class.from_xml(xml)

      expect(item.id).to eq("123")
      expect(item.value).to eq(42)
    end
  end

  context "with attributeFormDefault :qualified (W3C qualified)" do
    let(:namespace_class) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/ns"
        prefix_default "ex"
        element_form_default :qualified
        attribute_form_default :qualified  # Attributes MUST be qualified
      end
    end

    let(:model_class) do
      ns = namespace_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        attribute :value, :integer

        xml do
          element "item"
          namespace ns
          map_attribute "id", to: :id
          map_attribute "value", to: :value
        end
      end
    end

    it "serializes attributes WITH namespace prefix" do
      item = model_class.new(id: "123", value: 42)
      xml = item.to_xml(prefix: true)

      expect(xml).to include('<ex:item')
      expect(xml).to include('ex:id="123"')  # WITH prefix
      expect(xml).to include('ex:value="42"')  # WITH prefix
    end

    it "deserializes attributes with namespace prefix" do
      xml = '<ex:item xmlns:ex="http://example.com/ns" ex:id="123" ex:value="42"/>'
      item = model_class.from_xml(xml)

      expect(item.id).to eq("123")
      expect(item.value).to eq(42)
    end

    it "round-trips correctly" do
      original = model_class.new(id: "abc", value: 99)
      xml = original.to_xml(prefix: true)
      parsed = model_class.from_xml(xml)

      expect(parsed.id).to eq(original.id)
      expect(parsed.value).to eq(original.value)
    end
  end

  context "OOXML-like scenario (user bug report)" do
    let(:word_processing_ml) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        prefix_default "w"
        element_form_default :qualified
        attribute_form_default :qualified  # OOXML requires qualified attributes
      end
    end

    let(:spacing_class) do
      ns = word_processing_ml
      Class.new(Lutaml::Model::Serializable) do
        attribute :val, :integer
        attribute :after, :integer
        attribute :before, :integer

        xml do
          element "spacing"
          namespace ns
          map_attribute "val", to: :val
          map_attribute "after", to: :after
          map_attribute "before", to: :before
        end
      end
    end

    it "generates OOXML-compliant XML with prefixed attributes" do
      spacing = spacing_class.new(val: 20, after: 100, before: 0)
      xml = spacing.to_xml(prefix: true)

      # All attributes should have w: prefix per OOXML spec
      expect(xml).to include('<w:spacing')
      expect(xml).to include('w:val="20"')
      expect(xml).to include('w:after="100"')
      expect(xml).to include('w:before="0"')

      # Should NOT have unprefixed attributes
      expect(xml).not_to match(/\sval="/)
      expect(xml).not_to match(/\safter="/)
      expect(xml).not_to match(/\sbefore="/)
    end

    it "parses OOXML-compliant XML correctly" do
      xml = '<w:spacing xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" w:val="20" w:after="100" w:before="0"/>'
      spacing = spacing_class.from_xml(xml)

      expect(spacing.val).to eq(20)
      expect(spacing.after).to eq(100)
      expect(spacing.before).to eq(0)
    end
  end

  context "explicit attribute namespace overrides form default" do
    let(:namespace1) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/ns1"
        prefix_default "ns1"
        attribute_form_default :unqualified
      end
    end

    let(:namespace2) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/ns2"
        prefix_default "ns2"
      end
    end

    # Create custom type for explicit namespace attribute
    let(:ns2_string) do
      ns2 = namespace2
      Class.new(Lutaml::Model::Type::String) do
        xml_namespace ns2
      end
    end

    let(:model_class) do
      ns1 = namespace1
      ns2_type = ns2_string
      Class.new(Lutaml::Model::Serializable) do
        attribute :normal_attr, :string
        attribute :explicit_attr, ns2_type

        xml do
          element "item"
          namespace ns1
          map_attribute "normal", to: :normal_attr
          map_attribute "explicit", to: :explicit_attr
        end
      end
    end

    it "uses explicit namespace even when form_default is unqualified" do
      item = model_class.new(normal_attr: "a", explicit_attr: "b")
      xml = item.to_xml(prefix: true)

      expect(xml).to include('normal="a"')  # Unqualified (form default)
      expect(xml).to include('ns2:explicit="b"')  # Qualified (type namespace)
    end
  end

  context "type-level attribute namespace takes precedence" do
    let(:namespace_class) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/ns"
        prefix_default "ex"
        attribute_form_default :unqualified
      end
    end

    let(:type_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/type-ns"
        prefix_default "type"
      end
    end

    let(:custom_type) do
      ns = type_namespace
      Class.new(Lutaml::Model::Type::String) do
        xml_namespace ns
      end
    end

    let(:model_class) do
      ns = namespace_class
      type = custom_type
      Class.new(Lutaml::Model::Serializable) do
        attribute :normal, :string
        attribute :typed, type

        xml do
          element "item"
          namespace ns
          map_attribute "normal", to: :normal
          map_attribute "typed", to: :typed
        end
      end
    end

    it "uses type namespace even when form_default is unqualified" do
      item = model_class.new(normal: "a", typed: "b")
      xml = item.to_xml(prefix: true)

      expect(xml).to include('normal="a"')  # Unqualified (form default)
      expect(xml).to include('type:typed="b"')  # Qualified (type namespace)
    end
  end
end
