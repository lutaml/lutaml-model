require "spec_helper"
require "lutaml/model"

# Define all test classes in a module to prevent namespace pollution
module XmlSchemaPrimerFeaturesSpec
  # Namespaces
  class PoNamespace < Lutaml::Xml::W3c::XmlNamespace
    uri "http://example.com/po"
    prefix_default "po"
  end

  class PoNamespaceQualified < Lutaml::Xml::W3c::XmlNamespace
    uri "http://example.com/po"
    prefix_default "po"
    element_form_default :qualified
  end

  class PoNamespacePrefixed < Lutaml::Xml::W3c::XmlNamespace
    uri "http://example.com/po"
    prefix_default "po"
    element_form_default :qualified
  end

  class MixedNamespace < Lutaml::Xml::W3c::XmlNamespace
    uri "http://example.com/mixed"
    prefix_default "mx"
    element_form_default :qualified
  end

  # type_name (Model as complexType) - Basic tests
  class AddressType < Lutaml::Model::Serializable
    attribute :street, :string
    attribute :city, :string

    xml do
      type_name "AddressType" # Defines complexType, not element
      map_element "street", to: :street
      map_element "city", to: :city
    end
  end

  class Person < Lutaml::Model::Serializable
    attribute :home_address, AddressType
    attribute :work_address, AddressType

    xml do
      root "Person"
      map_element "homeAddress", to: :home_address
      map_element "workAddress", to: :work_address
    end
  end

  # type_name with namespace
  class UsAddress < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :street, :string
    attribute :city, :string

    xml do
      type_name "UsAddressType"
      namespace PoNamespace
      map_element "name", to: :name
      map_element "street", to: :street
      map_element "city", to: :city
    end
  end

  class PurchaseOrder < Lutaml::Model::Serializable
    attribute :ship_to, UsAddress

    xml do
      root "purchaseOrder"
      namespace PoNamespace
      map_element "shipTo", to: :ship_to
    end
  end

  # Per-element form override
  class Address < Lutaml::Model::Serializable
    attribute :name, :string
  end

  class PurchaseOrderWithOverride < Lutaml::Model::Serializable
    attribute :ship_to, Address
    attribute :comment, :string

    xml do
      root "purchaseOrder"
      namespace PoNamespaceQualified

      map_element "shipTo", to: :ship_to
      map_element "comment", to: :comment, form: :unqualified
    end
  end

  # Per-element form override with prefix format
  class Address2 < Lutaml::Model::Serializable
    attribute :name, :string
  end

  class PurchaseOrderPrefixed < Lutaml::Model::Serializable
    attribute :ship_to, Address2
    attribute :comment, :string

    xml do
      root "purchaseOrder"
      namespace PoNamespacePrefixed

      map_element "shipTo", to: :ship_to
      map_element "comment", to: :comment, form: :unqualified
    end
  end

  # Combining type_name with per-element form override
  class ContactType < Lutaml::Model::Serializable
    attribute :email, :string
    attribute :phone, :string

    xml do
      type_name "ContactType"
      namespace MixedNamespace
      map_element "email", to: :email
      map_element "phone", to: :phone
    end
  end

  class Supplier < Lutaml::Model::Serializable
    attribute :contact, ContactType
    attribute :notes, :string

    xml do
      root "supplier"
      namespace MixedNamespace

      map_element "contact", to: :contact
      map_element "notes", to: :notes, form: :unqualified
    end
  end
end

RSpec.describe "XML Schema Primer Features" do
  describe "type_name (Model as complexType)" do
    it "serializes reusable type embedded in parent elements" do
      person = XmlSchemaPrimerFeaturesSpec::Person.new(
        home_address: XmlSchemaPrimerFeaturesSpec::AddressType.new(
          street: "123 Home St", city: "Hometown",
        ),
        work_address: XmlSchemaPrimerFeaturesSpec::AddressType.new(
          street: "456 Work Ave", city: "Worktown",
        ),
      )

      expected_xml = <<~XML
        <Person>
          <homeAddress>
            <street>123 Home St</street>
            <city>Hometown</city>
          </homeAddress>
          <workAddress>
            <street>456 Work Ave</street>
            <city>Worktown</city>
          </workAddress>
        </Person>
      XML

      expect(person.to_xml).to be_xml_equivalent_to(expected_xml)
    end

    it "deserializes reusable type from XML" do
      xml_input = <<~XML
        <Person>
          <homeAddress>
            <street>123 Home St</street>
            <city>Hometown</city>
          </homeAddress>
          <workAddress>
            <street>456 Work Ave</street>
            <city>Worktown</city>
          </workAddress>
        </Person>
      XML

      person = XmlSchemaPrimerFeaturesSpec::Person.from_xml(xml_input)

      expect(person.home_address.street).to eq("123 Home St")
      expect(person.home_address.city).to eq("Hometown")
      expect(person.work_address.street).to eq("456 Work Ave")
      expect(person.work_address.city).to eq("Worktown")
    end

    it "round-trips XML with reusable type" do
      original = XmlSchemaPrimerFeaturesSpec::Person.new(
        home_address: XmlSchemaPrimerFeaturesSpec::AddressType.new(
          street: "123 Home St", city: "Hometown",
        ),
        work_address: XmlSchemaPrimerFeaturesSpec::AddressType.new(
          street: "456 Work Ave", city: "Worktown",
        ),
      )

      xml = original.to_xml
      parsed = XmlSchemaPrimerFeaturesSpec::Person.from_xml(xml)

      expect(parsed.home_address.street).to eq(original.home_address.street)
      expect(parsed.home_address.city).to eq(original.home_address.city)
      expect(parsed.work_address.street).to eq(original.work_address.street)
      expect(parsed.work_address.city).to eq(original.work_address.city)
    end
  end

  describe "type_name with namespace" do
    it "serializes namespaced reusable type" do
      po = XmlSchemaPrimerFeaturesSpec::PurchaseOrder.new(
        ship_to: XmlSchemaPrimerFeaturesSpec::UsAddress.new(name: "Alice",
                                                            street: "123 Main St", city: "Anytown"),
      )

      # W3C Compliance: When elementFormDefault="unqualified", local elements are in no namespace
      # Child elements must declare xmlns="" to opt out of parent's default namespace
      expected_xml = <<~XML
        <purchaseOrder xmlns="http://example.com/po">
          <shipTo>
            <name xmlns="">Alice</name>
            <street xmlns="">123 Main St</street>
            <city xmlns="">Anytown</city>
          </shipTo>
        </purchaseOrder>
      XML

      expect(po.to_xml).to be_xml_equivalent_to(expected_xml)
    end

    it "deserializes namespaced reusable type" do
      xml_input = <<~XML
        <purchaseOrder xmlns="http://example.com/po">
          <shipTo>
            <name>Alice</name>
            <street>123 Main St</street>
            <city>Anytown</city>
          </shipTo>
        </purchaseOrder>
      XML

      po = XmlSchemaPrimerFeaturesSpec::PurchaseOrder.from_xml(xml_input)

      expect(po.ship_to.name).to eq("Alice")
      expect(po.ship_to.street).to eq("123 Main St")
      expect(po.ship_to.city).to eq("Anytown")
    end
  end

  describe "Per-element form override" do
    it "serializes with mixed qualification using form override" do
      po = XmlSchemaPrimerFeaturesSpec::PurchaseOrderWithOverride.new(
        ship_to: XmlSchemaPrimerFeaturesSpec::Address.new(name: "Alice Smith"),
        comment: "Hurry, my lawn is going wild!",
      )

      expected_xml = <<~XML
        <purchaseOrder xmlns="http://example.com/po">
          <shipTo>
            <name>Alice Smith</name>
          </shipTo>
          <comment xmlns="">Hurry, my lawn is going wild!</comment>
        </purchaseOrder>
      XML

      expect(po.to_xml).to be_xml_equivalent_to(expected_xml)
    end

    it "deserializes with mixed qualification" do
      xml_input = <<~XML
        <purchaseOrder xmlns="http://example.com/po">
          <shipTo>
            <name>Alice Smith</name>
          </shipTo>
          <comment xmlns="">Hurry, my lawn is going wild!</comment>
        </purchaseOrder>
      XML

      po = XmlSchemaPrimerFeaturesSpec::PurchaseOrderWithOverride.from_xml(xml_input)

      expect(po.ship_to.name).to eq("Alice Smith")
      expect(po.comment).to eq("Hurry, my lawn is going wild!")
    end

    it "round-trips with mixed qualification" do
      original = XmlSchemaPrimerFeaturesSpec::PurchaseOrderWithOverride.new(
        ship_to: XmlSchemaPrimerFeaturesSpec::Address.new(name: "Alice Smith"),
        comment: "Hurry, my lawn is going wild!",
      )

      xml = original.to_xml
      parsed = XmlSchemaPrimerFeaturesSpec::PurchaseOrderWithOverride.from_xml(xml)

      expect(parsed.ship_to.name).to eq(original.ship_to.name)
      expect(parsed.comment).to eq(original.comment)
    end
  end

  describe "Per-element form override with prefix format" do
    it "serializes with prefix format and unqualified override" do
      po = XmlSchemaPrimerFeaturesSpec::PurchaseOrderPrefixed.new(
        ship_to: XmlSchemaPrimerFeaturesSpec::Address2.new(name: "Alice"),
        comment: "Urgent",
      )

      expected_xml = <<~XML
        <po:purchaseOrder xmlns:po="http://example.com/po">
          <shipTo>
            <name>Alice</name>
          </shipTo>
          <comment>Urgent</comment>
        </po:purchaseOrder>
      XML

      expect(po.to_xml(prefix: true)).to be_xml_equivalent_to(expected_xml)
    end

    it "deserializes prefix format with unqualified element" do
      xml_input = <<~XML
        <po:purchaseOrder xmlns:po="http://example.com/po">
          <po:shipTo>
            <name>Alice</name>
          </po:shipTo>
          <comment>Urgent</comment>
        </po:purchaseOrder>
      XML

      po = XmlSchemaPrimerFeaturesSpec::PurchaseOrderPrefixed.from_xml(xml_input)

      expect(po.ship_to.name).to eq("Alice")
      expect(po.comment).to eq("Urgent")
    end
  end

  describe "Combining type_name with per-element form override" do
    it "serializes complexType with form override" do
      supplier = XmlSchemaPrimerFeaturesSpec::Supplier.new(
        contact: XmlSchemaPrimerFeaturesSpec::ContactType.new(
          email: "test@example.com", phone: "555-1234",
        ),
        notes: "Preferred vendor",
      )

      expected_xml = <<~XML
        <supplier xmlns="http://example.com/mixed">
          <contact>
            <email>test@example.com</email>
            <phone>555-1234</phone>
          </contact>
          <notes xmlns="">Preferred vendor</notes>
        </supplier>
      XML

      expect(supplier.to_xml).to be_xml_equivalent_to(expected_xml)
    end

    it "deserializes complexType with form override" do
      xml_input = <<~XML
        <supplier xmlns="http://example.com/mixed">
          <contact>
            <email>test@example.com</email>
            <phone>555-1234</phone>
          </contact>
          <notes xmlns="">Preferred vendor</notes>
        </supplier>
      XML

      supplier = XmlSchemaPrimerFeaturesSpec::Supplier.from_xml(xml_input)

      expect(supplier.contact.email).to eq("test@example.com")
      expect(supplier.contact.phone).to eq("555-1234")
      expect(supplier.notes).to eq("Preferred vendor")
    end

    it "round-trips complexType with form override" do
      original = XmlSchemaPrimerFeaturesSpec::Supplier.new(
        contact: XmlSchemaPrimerFeaturesSpec::ContactType.new(
          email: "test@example.com", phone: "555-1234",
        ),
        notes: "Preferred vendor",
      )

      xml = original.to_xml
      parsed = XmlSchemaPrimerFeaturesSpec::Supplier.from_xml(xml)

      expect(parsed.contact.email).to eq(original.contact.email)
      expect(parsed.contact.phone).to eq(original.contact.phone)
      expect(parsed.notes).to eq(original.notes)
    end
  end
end
