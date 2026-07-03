require "spec_helper"
require "lutaml/model/schema"
require "nokogiri"

module SchemaGeneration
  class Glaze < Lutaml::Model::Serializable
    attribute :color, Lutaml::Model::Type::String
    attribute :finish, Lutaml::Model::Type::String
  end

  class Vase < Lutaml::Model::Serializable
    attribute :height, Lutaml::Model::Type::Float
    attribute :diameter, Lutaml::Model::Type::Float
    attribute :glaze, Glaze
    attribute :materials, Lutaml::Model::Type::String, collection: true
  end
end

RSpec.describe Lutaml::Xml::Schema::XsdSchema do
  describe ".generate" do
    it "generates an XSD schema for nested Serialize objects" do
      schema = described_class.generate(SchemaGeneration::Vase, pretty: true)

      expected_schema = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="SchemaGeneration::Vase">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="height" type="xs:float"/>
                <xs:element name="diameter" type="xs:float"/>
                <xs:element name="glaze">
                  <xs:complexType>
                    <xs:sequence>
                      <xs:element name="color" type="xs:string"/>
                      <xs:element name="finish" type="xs:string"/>
                    </xs:sequence>
                  </xs:complexType>
                </xs:element>
                <xs:element name="materials" minOccurs="0" maxOccurs="unbounded">
                  <xs:complexType>
                    <xs:sequence>
                      <xs:element name="item" type="xs:string"/>
                    </xs:sequence>
                  </xs:complexType>
                </xs:element>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
      XSD

      expect(schema).to eq(expected_schema)
    end
  end

  # Regression guard for issue #717: the generated XSD bound the XSD namespace
  # only as the default xmlns while referencing built-in types with an
  # undeclared "xs:" prefix, so no XSD processor could load the output.
  describe "generated XSD validity (issue #717)" do
    it "produces a schema Nokogiri can load (no target namespace)" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        xml do
          root "address"
          map_element "id", to: :id
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      expect(xsd).to include('<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"')
      expect(xsd).to include('type="xs:string"')
      expect { Nokogiri::XML::Schema(xsd) }.not_to raise_error
    end

    it "produces a schema Nokogiri can load (with target namespace)" do
      ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/addr"
        prefix_default "ex"
        element_form_default :qualified
      end
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :street, :string
        xml do
          root "address"
          namespace ns
          map_element "street", to: :street
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      expect(xsd).to include('xmlns:xs="http://www.w3.org/2001/XMLSchema"')
      expect(xsd).to include('targetNamespace="http://example.com/addr"')
      expect { Nokogiri::XML::Schema(xsd) }.not_to raise_error
    end

    # The hole #717 fell through: a nested named-type reference under a target
    # namespace must be prefixed, or it resolves to no-namespace and fails.
    it "qualifies named-type references under a target namespace" do
      ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/addr"
        prefix_default "ex"
        element_form_default :qualified
      end
      widget = Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        xml do
          root "widget"
          type_name "WidgetType"
          map_element "label", to: :label
        end
      end
      doc = Class.new(Lutaml::Model::Serializable) do
        attribute :widget, widget
        attribute :title, :string
        xml do
          root "doc"
          namespace ns
          map_element "widget", to: :widget
          map_element "title", to: :title
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(doc)

      expect(xsd).to include('xmlns:ex="http://example.com/addr"')
      expect(xsd).to include('type="ex:WidgetType"')
      expect(xsd).to include('<xs:complexType name="WidgetType">')
      expect(xsd).not_to include("<xs:import")
      expect { Nokogiri::XML::Schema(xsd) }.not_to raise_error
    end

    # Guard against over-eager prefixing: with no namespace, named-type refs
    # must stay unqualified (they resolve to no-namespace, which is valid).
    it "leaves named-type references unqualified when there is no namespace" do
      inner = Class.new(Lutaml::Model::Serializable) do
        attribute :city, :string
        xml do
          root "address"
          type_name "AddressType"
          map_element "city", to: :city
        end
      end
      outer = Class.new(Lutaml::Model::Serializable) do
        attribute :address, inner
        xml do
          root "person"
          map_element "address", to: :address
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(outer)

      expect(xsd).to include('type="AddressType"')
      expect(xsd).not_to include('type=":AddressType"')
      expect { Nokogiri::XML::Schema(xsd) }.not_to raise_error
    end

    it "qualifies named-type references for collections under a target namespace" do
      ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/addr"
        prefix_default "ex"
        element_form_default :qualified
      end
      item = Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        xml do
          root "item"
          type_name "ItemType"
          map_element "label", to: :label
        end
      end
      doc = Class.new(Lutaml::Model::Serializable) do
        attribute :items, item, collection: true
        xml do
          root "doc"
          namespace ns
          map_element "item", to: :items
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(doc)

      expect(xsd).to include('type="ex:ItemType"')
      expect { Nokogiri::XML::Schema(xsd) }.not_to raise_error
    end

    # A nested model in its OWN (different) namespace is imported and referenced
    # by its own prefix, NOT folded into the root namespace. (A schema document
    # has a single targetNamespace, so its type lives in its own schema.)
    it "imports and prefixes a nested model that declares a different namespace" do
      w_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://w.example/w"
        prefix_default "w"
        element_form_default :qualified
        schema_location "widget.xsd"
      end
      ex_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://ex.example/ex"
        prefix_default "ex"
        element_form_default :qualified
      end
      widget = Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        xml do
          root "widget"
          namespace w_ns
          type_name "WidgetType"
          map_element "label", to: :label
        end
      end
      doc = Class.new(Lutaml::Model::Serializable) do
        attribute :widget, widget
        xml do
          root "doc"
          namespace ex_ns
          map_element "widget", to: :widget
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(doc)

      # both namespaces declared, foreign one imported, ref uses its own prefix
      expect(xsd).to include('xmlns:w="http://w.example/w"')
      expect(xsd).to include('targetNamespace="http://ex.example/ex"')
      expect(xsd).to include('<xs:import namespace="http://w.example/w" schemaLocation="widget.xsd"/>')
      expect(xsd).to include('type="w:WidgetType"')
      # the foreign type is NOT defined in this document
      expect(xsd).not_to include('<xs:complexType name="WidgetType">')
    end

    # A target namespace whose class declares no prefix_default still needs a
    # usable prefix for named-type QNames; one is synthesised (tns).
    it "synthesises a prefix for a target namespace with no prefix_default" do
      ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/np"
        element_form_default :qualified
      end
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        xml do
          root "root"
          namespace ns
          type_name "RootType"
          map_element "id", to: :id
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      expect(xsd).to include('xmlns:tns="http://example.com/np"')
      expect(xsd).to include('type="tns:RootType"')
      expect { Nokogiri::XML::Schema(xsd) }.not_to raise_error
    end

    # Two different namespaces bound to the same prefix are unresolvable; the
    # generator raises rather than emit a silently-wrong QName.
    it "raises when two namespaces share a prefix" do
      a_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://a.example"
        prefix_default "p"
      end
      b_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://b.example"
        prefix_default "p"
      end
      child = Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        xml do
          root "child"
          namespace b_ns
          type_name "BType"
          map_element "v", to: :v
        end
      end
      parent = Class.new(Lutaml::Model::Serializable) do
        attribute :child, child
        xml do
          root "parent"
          namespace a_ns
          map_element "child", to: :child
        end
      end

      expect { Lutaml::Model::Schema.to_xsd(parent) }
        .to raise_error(Lutaml::Model::Error, /prefix 'p' is bound to two/)
    end

    # A recursive model (A -> B -> A) must terminate and define both types.
    it "handles recursive model references without overflowing" do
      rec_a = Class.new(Lutaml::Model::Serializable)
      rec_b = Class.new(Lutaml::Model::Serializable) do
        attribute :a, rec_a
        xml do
          root "b"
          type_name "BType"
          map_element "a", to: :a
        end
      end
      rec_a.class_eval do
        attribute :b, rec_b
        xml do
          root "a"
          type_name "AType"
          map_element "b", to: :b
        end
      end

      xsd = nil
      expect { xsd = Lutaml::Model::Schema.to_xsd(rec_a) }.not_to raise_error
      expect(xsd).to include('<xs:complexType name="AType">')
      expect(xsd).to include('<xs:complexType name="BType">')
    end

    # A foreign namespace with no usable prefix (nil, empty, or the reserved
    # "xs") cannot be referenced by a prefixed QName and must not borrow the
    # target prefix — raise instead.
    [nil, "", "xs"].each do |bad_prefix|
      it "raises for a foreign namespace with unusable prefix #{bad_prefix.inspect}" do
        foreign = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://foreign.example"
          prefix_default bad_prefix unless bad_prefix.nil?
          element_form_default :qualified
        end
        ex_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
          uri "http://ex.example/ex"
          prefix_default "ex"
        end
        child = Class.new(Lutaml::Model::Serializable) do
          attribute :v, :string
          xml do
            root "child"
            namespace foreign
            type_name "ForeignType"
            map_element "v", to: :v
          end
        end
        parent = Class.new(Lutaml::Model::Serializable) do
          attribute :child, child
          xml do
            root "parent"
            namespace ex_ns
            map_element "child", to: :child
          end
        end

        expect { Lutaml::Model::Schema.to_xsd(parent) }
          .to raise_error(Lutaml::Model::Error, /foreign namespace .* usable prefix/)
      end
    end
  end
end
