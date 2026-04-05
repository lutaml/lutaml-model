# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Namespace prefix with uri_aliases" do
  before do
    Lutaml::Model::GlobalContext.clear_caches
    Lutaml::Model::TransformationRegistry.instance.clear
    Lutaml::Model::GlobalRegister.instance.reset
    Lutaml::Xml::NamespaceClassRegistry.instance.clear!
  end

  after do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  # Oasis ETM namespace - uses alias URI in ISOSTS format
  let(:oasis_ns) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://docs.oasis-open.org/ns/oasis-exchange/table"
      uri_aliases "urn:oasis:names:tc:xml:table"
      prefix_default "oasis"
    end
  end

  let(:table_class) do
    ns = oasis_ns
    tgroupClass = Class.new(Lutaml::Model::Serializable) do
      attribute :cols, :integer
      xml do
        element "tgroup"
        namespace ns
        map_attribute "cols", to: :cols
      end
    end

    Class.new(Lutaml::Model::Serializable) do
      attribute :cols, :integer
      attribute :tgroup, tgroupClass

      xml do
        element "table"
        namespace ns

        map_attribute "cols", to: :cols
        map_element "tgroup", to: :tgroup
      end
    end
  end

  # ISOSTS format uses alias URI with prefix
  let(:isosts_xml) do
    <<~XML
      <oasis:table xmlns:oasis="urn:oasis:names:tc:xml:table" cols="2">
        <oasis:tgroup cols="2"/>
      </oasis:table>
    XML
  end

  describe "root element prefix behavior with alias URI" do
    let(:parsed_model) { table_class.from_xml(isosts_xml) }

    context "when input XML uses alias URI with prefix" do
      it "generates XML with prefix and alias URI preserved when no prefix option specified" do
        expected_xml = <<~XML
          <oasis:table xmlns:oasis="urn:oasis:names:tc:xml:table" cols="2">
            <oasis:tgroup cols="2"/>
          </oasis:table>
        XML
        expect(parsed_model.to_xml).to be_xml_equivalent_to(expected_xml)
      end

      it "generates XML with prefix_default and alias URI when prefix: true is specified" do
        expected_xml = <<~XML
          <oasis:table xmlns:oasis="urn:oasis:names:tc:xml:table" cols="2">
            <oasis:tgroup cols="2"/>
          </oasis:table>
        XML
        expect(parsed_model.to_xml(prefix: true)).to be_xml_equivalent_to(expected_xml)
      end

      it "generates XML without prefix but with alias URI when prefix: :default is specified" do
        expected_xml = <<~XML
          <table xmlns="urn:oasis:names:tc:xml:table" cols="2">
            <tgroup cols="2"/>
          </table>
        XML
        expect(parsed_model.to_xml(prefix: :default)).to be_xml_equivalent_to(expected_xml)
      end

      it "generates XML with custom prefix and alias URI when prefix: 'custom' is specified" do
        expected_xml = <<~XML
          <custom:table xmlns:custom="urn:oasis:names:tc:xml:table" cols="2">
            <custom:tgroup cols="2"/>
          </custom:table>
        XML
        expect(parsed_model.to_xml(prefix: "custom")).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "when input XML uses canonical URI with prefix" do
      let(:canonical_xml) do
        <<~XML
          <oasis:table xmlns:oasis="http://docs.oasis-open.org/ns/oasis-exchange/table" cols="2">
            <oasis:tgroup cols="2"/>
          </oasis:table>
        XML
      end
      let(:parsed_model) { table_class.from_xml(canonical_xml) }

      it "generates XML with prefix and canonical URI when prefix: true is specified" do
        expected_xml = <<~XML
          <oasis:table xmlns:oasis="http://docs.oasis-open.org/ns/oasis-exchange/table" cols="2">
            <oasis:tgroup cols="2"/>
          </oasis:table>
        XML
        expect(parsed_model.to_xml(prefix: true)).to be_xml_equivalent_to(expected_xml)
      end

      it "generates XML without prefix but with canonical URI when prefix: :default is specified" do
        expected_xml = <<~XML
          <table xmlns="http://docs.oasis-open.org/ns/oasis-exchange/table" cols="2">
            <tgroup cols="2"/>
          </table>
        XML
        expect(parsed_model.to_xml(prefix: :default)).to be_xml_equivalent_to(expected_xml)
      end
    end
  end
end
