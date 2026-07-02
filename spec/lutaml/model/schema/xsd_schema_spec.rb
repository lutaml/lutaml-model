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
  end
end
