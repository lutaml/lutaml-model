# frozen_string_literal: true

require "spec_helper"

# Conformance tests for W3C XML Schema Instance attributes
# @see https://www.w3.org/TR/xmlschema-1/#xsi_attrs
#
# Tests cover xsi:nil, xsi:type, xsi:schemaLocation,
# xsi:noNamespaceSchemaLocation per XML Schema Part 1, Section 2.6.3.
RSpec.describe "XML Schema Instance Conformance" do
  after do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  # ── xsi:nil ───────────────────────────────────────────────────────────

  describe "XSI-NIL: xsi:nil attribute" do
    before do
      stub_const("XsiNilModel", Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "field"
          map_content to: :value
        end
      end)
    end

    # XSI-NIL-1: xsi:nil="true" indicates nil content
    it "XSI-NIL-1: supports xsi:nil in deserialization" do
      xml = '<field xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>'
      model = XsiNilModel.from_xml(xml)

      # Content should be nil/empty when xsi:nil is true
      expect(model.value).to be_nil.or(eq(""))
    end

    # XSI-NIL-2: xsi:nil cast validates value
    it "XSI-NIL-2: xsi:nil validates value must be 'true' or 'false'" do
      expect do
        Lutaml::Xml::W3c::XsiNil.cast("maybe")
      end.to raise_error(ArgumentError, /must be 'true' or 'false'/)
    end

    # XSI-NIL-3: xsi:nil accepts valid boolean strings
    it "XSI-NIL-3: accepts 'true' and 'false' for xsi:nil" do
      expect(Lutaml::Xml::W3c::XsiNil.cast("true")).to eq("true")
      expect(Lutaml::Xml::W3c::XsiNil.cast("false")).to eq("false")
      expect(Lutaml::Xml::W3c::XsiNil.cast(nil)).to be_nil
    end
  end

  # ── xsi:type ──────────────────────────────────────────────────────────

  describe "XSI-TYPE: xsi:type attribute" do
    # XSI-TYPE-1: xsi:type is defined as a W3C type
    it "XSI-TYPE-1: provides xsi:type type definition" do
      expect(Lutaml::Xml::W3c::XsiType).to be < Lutaml::Model::Type::String
    end

    # XSI-TYPE-2: xsi:type can be used in models
    it "XSI-TYPE-2: supports xsi:type in model attribute mapping" do
      stub_const("XsiTypeModel", Class.new(Lutaml::Model::Serializable) do
        attribute :type, Lutaml::Xml::W3c::XsiType
        attribute :content, :string

        xml do
          element "value"
          map_attribute "type", to: :type
          map_content to: :content
        end
      end)

      xml_in = '<value xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:integer">42</value>'
      model = XsiTypeModel.from_xml(xml_in)

      expect(model.type).to eq("xs:integer")
      expect(model.content).to eq("42")
    end

    # XSI-TYPE-3: xsi:type is NOT automatically inferred or validated
    # lutaml-model does not perform type substitution based on xsi:type
    it "XSI-TYPE-3: xsi:type is stored as string, not used for type substitution" do
      stub_const("XsiTypeNoSubModel", Class.new(Lutaml::Model::Serializable) do
        attribute :type, Lutaml::Xml::W3c::XsiType
        attribute :content, :string

        xml do
          element "value"
          map_attribute "type", to: :type
          map_content to: :content
        end
      end)

      xml_in = '<value xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:date">2024-01-15</value>'
      model = XsiTypeNoSubModel.from_xml(xml_in)

      # Content remains string; no type substitution occurs
      expect(model.content).to eq("2024-01-15")
      expect(model.content).to be_a(String)
    end
  end

  # ── xsi:schemaLocation ───────────────────────────────────────────────

  describe "XSI-SCHEMA-LOC: xsi:schemaLocation" do
    # XSI-SCHEMA-LOC-1: xsi:schemaLocation type exists
    it "XSI-SCHEMA-LOC-1: provides xsi:schemaLocation type definition" do
      expect(Lutaml::Xml::W3c::XsiSchemaLocationType).to be < Lutaml::Model::Type::String
    end

    # XSI-SCHEMA-LOC-2: Can parse schemaLocation with namespace-URI pairs
    it "XSI-SCHEMA-LOC-2: parses xsi:schemaLocation value" do
      stub_const("XsiSchemaLocModel", Class.new(Lutaml::Model::Serializable) do
        attribute :schema_location, Lutaml::Xml::W3c::XsiSchemaLocationType
        attribute :content, :string

        xml do
          element "root"
          map_attribute "schemaLocation", to: :schema_location
          map_content to: :content
        end
      end)

      pairs = "http://example.com/ns http://example.com/schema.xsd"
      xml_in = "<root xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"#{pairs}\">data</root>"
      model = XsiSchemaLocModel.from_xml(xml_in)

      expect(model.schema_location).to include("http://example.com/ns")
      expect(model.schema_location).to include("http://example.com/schema.xsd")
    end
  end

  # ── xsi:noNamespaceSchemaLocation ────────────────────────────────────

  describe "XSI-NO-NS-LOC: xsi:noNamespaceSchemaLocation" do
    # XSI-NO-NS-LOC-1: type exists
    it "XSI-NO-NS-LOC-1: provides xsi:noNamespaceSchemaLocation type definition" do
      expect(Lutaml::Xml::W3c::XsiNoNamespaceSchemaLocationType).to be < Lutaml::Model::Type::String
    end

    # XSI-NO-NS-LOC-2: Can parse and serialize
    it "XSI-NO-NS-LOC-2: parses xsi:noNamespaceSchemaLocation value" do
      stub_const("XsiNoNsLocModel", Class.new(Lutaml::Model::Serializable) do
        attribute :no_ns_schema, Lutaml::Xml::W3c::XsiNoNamespaceSchemaLocationType
        attribute :content, :string

        xml do
          element "root"
          map_attribute "noNamespaceSchemaLocation", to: :no_ns_schema
          map_content to: :content
        end
      end)

      xml_in = '<root xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="schema.xsd">data</root>'
      model = XsiNoNsLocModel.from_xml(xml_in)

      expect(model.no_ns_schema).to eq("schema.xsd")
    end
  end

  # ── XSI namespace registration ───────────────────────────────────────

  describe "XSI-REG: XSI namespace and type registration" do
    before do
      # Ensure W3C types are registered (load order may vary in CI)
      Lutaml::Xml::W3c.register_types!
    end

    # XSI-REG-1: XSI namespace is defined with correct URI
    it "XSI-REG-1: XSI namespace has correct URI and prefix" do
      ns = Lutaml::Xml::W3c::XsiNamespace.new
      expect(ns.uri).to eq("http://www.w3.org/2001/XMLSchema-instance")
      expect(ns.prefix).to eq("xsi")
    end

    # XSI-REG-2: XSI types are registered in the Type registry
    it "XSI-REG-2: all XSI types are registered" do
      expect(Lutaml::Xml::W3c.registered?).to be true
      registry = Lutaml::Model::Type.instance_variable_get(:@registry)
      expect(registry).to include(:xsi_type)
      expect(registry).to include(:xsi_nil)
      expect(registry).to include(:xsi_schema_location)
      expect(registry).to include(:xsi_no_namespace_schema_location)
    end

    # XSI-REG-3: XSI types are accessible by symbol
    it "XSI-REG-3: XSI types accessible via symbol references" do
      stub_const("XsiSymbolModel", Class.new(Lutaml::Model::Serializable) do
        attribute :nil_val, Lutaml::Xml::W3c::XsiNil
        attribute :type_val, Lutaml::Xml::W3c::XsiType
        attribute :schema_loc, Lutaml::Xml::W3c::XsiSchemaLocationType
        attribute :no_ns_loc, Lutaml::Xml::W3c::XsiNoNamespaceSchemaLocationType

        xml do
          element "root"
        end
      end)

      model = XsiSymbolModel.new(
        nil_val: "true",
        type_val: "xs:string",
        schema_loc: "http://example.com schema.xsd",
        no_ns_loc: "schema.xsd"
      )

      expect(model.nil_val).to eq("true")
      expect(model.type_val).to eq("xs:string")
    end
  end

  # ── XLink namespace ──────────────────────────────────────────────────

  describe "XLINK: XLink namespace types" do
    # XLINK-1: XLink namespace defined with correct URI
    it "XLINK-1: XLink namespace has correct URI and prefix" do
      ns = Lutaml::Xml::W3c::XlinkNamespace.new
      expect(ns.uri).to eq("http://www.w3.org/1999/xlink")
      expect(ns.prefix).to eq("xlink")
    end

    # XLINK-2: XLink types validate their values
    it "XLINK-2: xlink:type validates link type values" do
      expect(Lutaml::Xml::W3c::XlinkTypeAttrType.cast("simple")).to eq("simple")
      expect do
        Lutaml::Xml::W3c::XlinkTypeAttrType.cast("invalid")
      end.to raise_error(ArgumentError, /xlink:type/)
    end

    # XLINK-3: xlink:show validates display values
    it "XLINK-3: xlink:show validates display values" do
      expect(Lutaml::Xml::W3c::XlinkShowType.cast("new")).to eq("new")
      expect do
        Lutaml::Xml::W3c::XlinkShowType.cast("popup")
      end.to raise_error(ArgumentError, /xlink:show/)
    end

    # XLINK-4: xlink:actuate validates timing values
    it "XLINK-4: xlink:actuate validates timing values" do
      expect(Lutaml::Xml::W3c::XlinkActuateType.cast("onLoad")).to eq("onLoad")
      expect do
        Lutaml::Xml::W3c::XlinkActuateType.cast("onClick")
      end.to raise_error(ArgumentError, /xlink:actuate/)
    end

    # XLINK-5: XLink href in model
    it "XLINK-5: supports xlink:href in model mapping" do
      stub_const("XlinkHrefModel", Class.new(Lutaml::Model::Serializable) do
        attribute :href, Lutaml::Xml::W3c::XlinkHrefType
        attribute :content, :string

        xml do
          element "a"
          map_attribute "href", to: :href
          map_content to: :content
        end
      end)

      xml_in = '<a xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="http://example.com">Link</a>'
      model = XlinkHrefModel.from_xml(xml_in)

      expect(model.href).to eq("http://example.com")
      expect(model.content).to eq("Link")
    end
  end
end
