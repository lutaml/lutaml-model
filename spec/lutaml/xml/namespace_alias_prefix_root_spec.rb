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
    Class.new(Lutaml::Model::Serializable) do
      attribute :cols, :integer

      xml do
        root "table"
        namespace ns
        map_attribute "cols", to: :cols
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

  describe "root element prefix behavior" do
    context "when input XML uses alias URI with prefix" do
      let(:parsed_model) { table_class.from_xml(isosts_xml) }

      # Scenario 1: No prefix option → preserve input format
      it "generates XML with prefix preserved when no prefix option specified" do
        xml = parsed_model.to_xml
        # Should preserve the original prefix since input had a prefix
        expect(xml).to include("<oasis:table")
        expect(xml).to include('xmlns:oasis="urn:oasis:names:tc:xml:table"')
      end

      # Scenario 2: prefix: true → use namespace's prefix_default
      it "generates XML with prefix_default when prefix: true is specified" do
        xml = parsed_model.to_xml(prefix: true)
        # Should use namespace's prefix_default which is "oasis"
        expect(xml).to include("<oasis:table")
        expect(xml).to include('xmlns:oasis="http://docs.oasis-open.org/ns/oasis-exchange/table"')
      end

      # Scenario 3: prefix: :default → use default namespace format
      it "generates XML without prefix when prefix: :default is specified" do
        xml = parsed_model.to_xml(prefix: :default)
        # Should use default namespace format (no prefix on element)
        expect(xml).to include("<table xmlns=")
        expect(xml).to include('xmlns="http://docs.oasis-open.org/ns/oasis-exchange/table"')
      end

      # Scenario 4: prefix: 'custom' → use custom prefix
      it "generates XML with custom prefix when prefix: 'custom' is specified" do
        xml = parsed_model.to_xml(prefix: "custom")
        # Should use the custom prefix
        expect(xml).to include("<custom:table")
        expect(xml).to include('xmlns:custom="http://docs.oasis-open.org/ns/oasis-exchange/table"')
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

      it "generates XML with prefix when prefix: true is specified" do
        xml = parsed_model.to_xml(prefix: true)
        expect(xml).to include("<oasis:table")
        expect(xml).to include('xmlns:oasis="http://docs.oasis-open.org/ns/oasis-exchange/table"')
      end

      it "generates XML without prefix when prefix: :default is specified" do
        xml = parsed_model.to_xml(prefix: :default)
        expect(xml).to include("<table xmlns=")
        expect(xml).to include('xmlns="http://docs.oasis-open.org/ns/oasis-exchange/table"')
      end
    end
  end
end
