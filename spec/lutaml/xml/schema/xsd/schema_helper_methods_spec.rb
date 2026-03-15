# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::Schema, "helper methods" do
  let(:schema_content) do
    <<~XSD
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 targetNamespace="http://example.com/test"
                 xmlns:test="http://example.com/test"
                 elementFormDefault="qualified">

        <!-- Import statement -->
        <xs:import namespace="http://example.com/other" schemaLocation="other.xsd"/>

        <!-- Complex types -->
        <xs:complexType name="PersonType">
          <xs:sequence>
            <xs:element name="name" type="xs:string"/>
            <xs:element name="age" type="xs:integer"/>
          </xs:sequence>
        </xs:complexType>

        <xs:complexType name="AddressType">
          <xs:sequence>
            <xs:element name="street" type="xs:string"/>
            <xs:element name="city" type="xs:string"/>
          </xs:sequence>
        </xs:complexType>

        <!-- Simple types -->
        <xs:simpleType name="EmailType">
          <xs:restriction base="xs:string">
            <xs:pattern value="[^@]+@[^@]+"/>
          </xs:restriction>
        </xs:simpleType>

        <!-- Elements -->
        <xs:element name="person" type="test:PersonType"/>
        <xs:element name="address" type="test:AddressType"/>

        <!-- Attributes -->
        <xs:attribute name="id" type="xs:ID"/>

        <!-- Groups -->
        <xs:group name="PersonGroup">
          <xs:sequence>
            <xs:element name="firstName" type="xs:string"/>
            <xs:element name="lastName" type="xs:string"/>
          </xs:sequence>
        </xs:group>

        <!-- Attribute groups -->
        <xs:attributeGroup name="CommonAttributes">
          <xs:attribute name="version" type="xs:string"/>
        </xs:attributeGroup>
      </xs:schema>
    XSD
  end

  let(:parsed_schema) do
    Lutaml::Xml::Schema::Xsd.parse(schema_content)
  end

  describe "#find_complex_type" do
    it "finds an existing complex type by name" do
      result = parsed_schema.find_complex_type("PersonType")
      expect(result).not_to be_nil
      expect(result.name).to eq("PersonType")
    end

    it "finds another complex type by name" do
      result = parsed_schema.find_complex_type("AddressType")
      expect(result).not_to be_nil
      expect(result.name).to eq("AddressType")
    end

    it "returns nil for non-existent complex type" do
      result = parsed_schema.find_complex_type("NonExistentType")
      expect(result).to be_nil
    end

    it "returns nil when name is nil" do
      result = parsed_schema.find_complex_type(nil)
      expect(result).to be_nil
    end
  end

  describe "#find_simple_type" do
    it "finds an existing simple type by name" do
      result = parsed_schema.find_simple_type("EmailType")
      expect(result).not_to be_nil
      expect(result.name).to eq("EmailType")
    end

    it "returns nil for non-existent simple type" do
      result = parsed_schema.find_simple_type("NonExistentType")
      expect(result).to be_nil
    end

    it "returns nil when name is nil" do
      result = parsed_schema.find_simple_type(nil)
      expect(result).to be_nil
    end
  end

  describe "#find_element" do
    it "finds an existing element by name" do
      result = parsed_schema.find_element("person")
      expect(result).not_to be_nil
      expect(result.name).to eq("person")
    end

    it "finds another element by name" do
      result = parsed_schema.find_element("address")
      expect(result).not_to be_nil
      expect(result.name).to eq("address")
    end

    it "returns nil for non-existent element" do
      result = parsed_schema.find_element("nonExistent")
      expect(result).to be_nil
    end

    it "returns nil when name is nil" do
      result = parsed_schema.find_element(nil)
      expect(result).to be_nil
    end
  end

  describe "#stats" do
    it "returns a hash with statistics" do
      stats = parsed_schema.stats
      expect(stats).to be_a(Hash)
    end

    it "includes counts for all schema components" do
      stats = parsed_schema.stats
      expect(stats).to have_key(:elements)
      expect(stats).to have_key(:complex_types)
      expect(stats).to have_key(:simple_types)
      expect(stats).to have_key(:attributes)
      expect(stats).to have_key(:groups)
      expect(stats).to have_key(:attribute_groups)
      expect(stats).to have_key(:imports)
      expect(stats).to have_key(:includes)
      expect(stats).to have_key(:namespaces)
    end

    it "reports correct element count" do
      stats = parsed_schema.stats
      expect(stats[:elements]).to eq(2)
    end

    it "reports correct complex type count" do
      stats = parsed_schema.stats
      expect(stats[:complex_types]).to eq(2)
    end

    it "reports correct simple type count" do
      stats = parsed_schema.stats
      expect(stats[:simple_types]).to eq(1)
    end

    it "reports correct attribute count" do
      stats = parsed_schema.stats
      expect(stats[:attributes]).to eq(1)
    end

    it "reports correct group count" do
      stats = parsed_schema.stats
      expect(stats[:groups]).to eq(1)
    end

    it "reports correct attribute group count" do
      stats = parsed_schema.stats
      expect(stats[:attribute_groups]).to eq(1)
    end

    it "reports namespace count" do
      stats = parsed_schema.stats
      expect(stats[:namespaces]).to be >= 1
    end
  end

  describe "#valid?" do
    it "returns true when target namespace is present" do
      expect(parsed_schema.valid?).to be true
    end

    it "returns false when target namespace is empty" do
      empty_schema_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        </xs:schema>
      XSD
      empty_schema = Lutaml::Xml::Schema::Xsd.parse(empty_schema_content)
      expect(empty_schema.valid?).to be false
    end
  end

  describe "#summary" do
    it "returns a human-readable summary string" do
      summary = parsed_schema.summary
      expect(summary).to be_a(String)
      expect(summary).to include("http://example.com/test")
    end

    it "includes element count in summary" do
      summary = parsed_schema.summary
      expect(summary).to include("2 elements")
    end

    it "includes complex type count in summary" do
      summary = parsed_schema.summary
      expect(summary).to include("2 complex types")
    end

    it "includes simple type count in summary" do
      summary = parsed_schema.summary
      expect(summary).to include("1 simple type")
    end

    it "handles schema without namespace" do
      no_ns_schema_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="test" type="xs:string"/>
        </xs:schema>
      XSD
      no_ns_schema = Lutaml::Xml::Schema::Xsd.parse(no_ns_schema_content)
      summary = no_ns_schema.summary
      expect(summary).to include("(no namespace)")
    end
  end
end
