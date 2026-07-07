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

    # Namespaces used only INSIDE an imported foreign type belong to that
    # type's own schema document — they must not be declared, imported, or
    # validated here.
    it "ignores namespaces nested inside an imported foreign subtree" do
      inner_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://c.example" # deliberately no prefix_default
      end
      w_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://w.example/w"
        prefix_default "w"
        schema_location "widget.xsd"
      end
      ex_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://ex.example/ex"
        prefix_default "ex"
      end
      inner = Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        xml do
          root "inner"
          namespace inner_ns
          type_name "InnerType"
          map_element "v", to: :v
        end
      end
      widget = Class.new(Lutaml::Model::Serializable) do
        attribute :inner, inner
        xml do
          root "widget"
          namespace w_ns
          type_name "WidgetType"
          map_element "inner", to: :inner
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

      expect(xsd).to include('type="w:WidgetType"')
      expect(xsd).not_to include("http://c.example")
    end

    it "raises when a foreign namespace has no schema_location" do
      w_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://w-noloc.example/w"
        prefix_default "w" # no schema_location
      end
      ex_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://ex.example/ex"
        prefix_default "ex"
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

      expect { Lutaml::Model::Schema.to_xsd(doc) }
        .to raise_error(Lutaml::Model::Error, /schema_location/)
    end

    it "downgrades foreign-namespace errors to warnings under skip_validation" do
      w_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://w-warn.example/w"
        prefix_default "w" # no schema_location -> error without skip_validation
      end
      ex_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://ex.example/ex"
        prefix_default "ex"
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

      xsd = nil
      expect { xsd = Lutaml::Model::Schema.to_xsd(doc, skip_validation: true) }
        .to output(/schema_location/).to_stderr

      # Best-effort output still declares the usable prefix its QNames use,
      # and imports the namespace (location-less).
      expect(xsd).to include('xmlns:w="http://w-warn.example/w"')
      expect(xsd).to include('type="w:WidgetType"')
      expect(xsd).to include('<xs:import namespace="http://w-warn.example/w"/>')
    end

    # Prefix errors emit QNames that resolve to the WRONG namespace, so they
    # stay hard errors even under skip_validation.
    it "does not downgrade prefix errors under skip_validation" do
      no_pfx = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://p-hard.example" # no prefix_default
      end
      ex_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://ex.example/ex"
        prefix_default "ex"
      end
      child = Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        xml do
          root "child"
          namespace no_pfx
          type_name "PType"
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

      expect do
        Lutaml::Model::Schema.to_xsd(parent, skip_validation: true)
      end.to raise_error(Lutaml::Model::Error, /usable prefix/)
    end

    # A Type::Value attribute type that declares its own namespace resolves
    # through that namespace's imported schema.
    it "declares and imports a Type::Value attribute type's namespace" do
      gml_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://www.opengis.net/gml"
        prefix_default "gml"
        schema_location "gml.xsd"
      end
      measure = Class.new(Lutaml::Model::Type::String) do
        xml { namespace gml_ns }
        xsd_type "gml:MeasureType"
      end
      doc = Class.new(Lutaml::Model::Serializable) do
        attribute :measure, measure
        xml do
          root "doc"
          map_element "measure", to: :measure
        end
      end

      # skip_validation matches main's behavior for namespaced custom types;
      # accepting them in validation is a deferred follow-up.
      xsd = Lutaml::Model::Schema.to_xsd(doc, skip_validation: true)

      expect(xsd).to include('xmlns:gml="http://www.opengis.net/gml"')
      expect(xsd).to include('<xs:import namespace="http://www.opengis.net/gml" schemaLocation="gml.xsd"/>')
      expect(xsd).to include('type="gml:MeasureType"')
    end

    it "synthesizes a non-colliding prefix when a foreign namespace claims tns" do
      no_pfx_target = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/np" # no prefix_default -> synthesized
      end
      tns_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://t.example"
        prefix_default "tns"
        schema_location "t.xsd"
      end
      child = Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        xml do
          root "child"
          namespace tns_ns
          type_name "TType"
          map_element "v", to: :v
        end
      end
      doc = Class.new(Lutaml::Model::Serializable) do
        attribute :child, child
        attribute :id, :string
        xml do
          root "doc"
          namespace no_pfx_target
          type_name "DocType"
          map_element "child", to: :child
          map_element "id", to: :id
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(doc)

      expect(xsd).to include('xmlns:tns="http://t.example"')
      expect(xsd).to include('xmlns:tns1="http://example.com/np"')
      expect(xsd).to include('type="tns1:DocType"')
      expect(xsd).to include('type="tns:TType"')
    end

    # A foreign-namespaced nested model with NO type_name is inlined into this
    # document (like a same-namespace model), not imported — so its namespace
    # must not trigger the foreign-import schema_location requirement. The
    # namespace walk and the element walk must agree that it is not a boundary.
    it "does not require schema_location for an inlined (type_name-less) foreign model" do
      inner_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://inner.example/in"
        prefix_default "in" # no schema_location, no type_name below
      end
      outer_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://outer.example/out"
        prefix_default "out"
      end
      inner = Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        xml do
          root "inner"
          namespace inner_ns
          map_element "label", to: :label
        end
      end
      outer = Class.new(Lutaml::Model::Serializable) do
        attribute :inner, inner
        xml do
          root "outer"
          namespace outer_ns
          map_element "inner", to: :inner
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(outer)

      # Inlined, not imported: its content appears here, no <xs:import> for it.
      expect(xsd).to include('name="label"')
      expect(xsd).not_to include("http://inner.example/in")
    end

    it "does not emit a spurious import for an inlined foreign model with a schema_location" do
      inner_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://inner2.example/in"
        prefix_default "in"
        schema_location "inner.xsd" # present, but model has no type_name
      end
      outer_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://outer2.example/out"
        prefix_default "out"
      end
      inner = Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        xml do
          root "inner"
          namespace inner_ns
          map_element "label", to: :label
        end
      end
      outer = Class.new(Lutaml::Model::Serializable) do
        attribute :inner, inner
        xml do
          root "outer"
          namespace outer_ns
          map_element "inner", to: :inner
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(outer)

      expect(xsd).to include('name="label"')
      expect(xsd).not_to include("<xs:import")
    end

    # A prefix bound to two different namespaces — a foreign model vs a
    # Type::Value type sharing a prefix_default — is unresolvable and must
    # raise, not silently keep the first binding.
    it "raises when a foreign model and a Type::Value share a prefix for different namespaces" do
      model_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://model.example/gml"
        prefix_default "gml"
        schema_location "model.xsd"
      end
      type_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://type.example/gml"
        prefix_default "gml"
        schema_location "type.xsd"
      end
      measure = Class.new(Lutaml::Model::Type::String) do
        xml { namespace type_ns }
        xsd_type "gml:MeasureType"
      end
      widget = Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        xml do
          root "widget"
          namespace model_ns
          type_name "WidgetType"
          map_element "label", to: :label
        end
      end
      target_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://doc.example/doc"
        prefix_default "doc"
      end
      doc = Class.new(Lutaml::Model::Serializable) do
        attribute :size, measure
        attribute :widget, widget
        xml do
          root "doc"
          namespace target_ns
          map_element "size", to: :size
          map_element "widget", to: :widget
        end
      end

      # Raises even under skip_validation — a wrong-namespace QName is never
      # recoverable, matching the foreign prefix-collision behavior.
      expect do
        Lutaml::Model::Schema.to_xsd(doc, skip_validation: true)
      end.to raise_error(Lutaml::Model::Error, /two different namespaces/)
    end

    # A collection of a type_name-less model renders as a placeholder `item`
    # element, so nothing inside it is emitted — the namespace walk must not
    # descend into it and import a foreign type the schema never references.
    it "does not import namespaces reachable only through a placeholder collection" do
      child_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://child.example/ch"
        prefix_default "ch" # foreign + type_name + NO schema_location
      end
      inner_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://binner.example/b"
        prefix_default "bin"
      end
      child = Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        xml do
          root "child"
          namespace child_ns
          type_name "ChildType"
          map_element "v", to: :v
        end
      end
      inner = Class.new(Lutaml::Model::Serializable) do
        attribute :child, child
        xml do
          root "inner"
          namespace inner_ns
          map_element "child", to: :child
        end
      end
      root_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://root.example/r"
        prefix_default "r"
      end
      root = Class.new(Lutaml::Model::Serializable) do
        attribute :inners, inner, collection: true
        xml do
          root "root"
          namespace root_ns
          map_element "inner", to: :inners
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(root)

      # No spurious import/raise for the foreign child reachable only through
      # the placeholder collection.
      expect(xsd).not_to include("http://child.example/ch")
      expect(xsd).not_to include("http://binner.example/b")
    end

    # Locks the deliberate skip-before-cycle-guard ordering: a model referenced
    # BOTH as a placeholder collection and as a single inlined attribute must
    # still be inlined via the single path — the placeholder reference must not
    # consume the model's cycle-guard slot and mask the emitted one. Regardless
    # of attribute order, the inlined model's nested named type stays defined.
    %i[collection_first single_first].each do |order|
      it "defines a nested type of a model also referenced as a placeholder collection (#{order})" do
        child = Class.new(Lutaml::Model::Serializable) do
          attribute :v, :string
          xml do
            root "child"
            type_name "CType"
            map_element "v", to: :v
          end
        end
        mid = Class.new(Lutaml::Model::Serializable) do
          attribute :child, child
          xml do
            root "mid"
            map_element "child", to: :child
          end
        end
        root = Class.new(Lutaml::Model::Serializable) do
          if order == :collection_first
            attribute :many, mid, collection: true
            attribute :one, mid
          else
            attribute :one, mid
            attribute :many, mid, collection: true
          end
          xml do
            root "root"
            map_element "many", to: :many
            map_element "one", to: :one
          end
        end

        xsd = Lutaml::Model::Schema.to_xsd(root)

        # The single-inline path references CType, so CType must be defined —
        # even when the placeholder collection references `mid` first.
        expect(xsd).to include('<xs:complexType name="CType">')
        expect { Nokogiri::XML::Schema(xsd) }.not_to raise_error
      end
    end

    # When the root schema has no targetNamespace, the foreign-prefix error must
    # not interpolate a nil target into a confusing "'' schema" string.
    it "reports the no-namespace schema clearly in the foreign-prefix error" do
      foreign_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://foreign.example/f"
        prefix_default "xs" # reserved -> unusable prefix, triggers the error
      end
      child = Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        xml do
          root "child"
          namespace foreign_ns
          type_name "ChildType"
          map_element "v", to: :v
        end
      end
      root = Class.new(Lutaml::Model::Serializable) do
        attribute :child, child
        xml do
          root "root" # no namespace -> target_uri is nil
          map_element "child", to: :child
        end
      end

      expect { Lutaml::Model::Schema.to_xsd(root) }
        .to raise_error(Lutaml::Model::Error, /this no-namespace schema/)
    end
  end
end
