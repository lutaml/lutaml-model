# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml/adapter/nokogiri_adapter"
require "lutaml/xml/adapter/ox_adapter"
require "lutaml/xml/adapter/oga_adapter"
require "lutaml/xml/adapter/rexml_adapter"

RSpec.describe "Processing Instructions" do
  describe "XmlElement data model" do
    it "stores processing instructions on an XmlElement" do
      elem = Lutaml::Xml::DataModel::XmlElement.new("root")
      elem.add_processing_instruction("rfc", 'strict="yes"')
      elem.add_processing_instruction("rfc", 'compact="yes"')

      expect(elem.processing_instructions.length).to eq(2)
      expect(elem.processing_instructions[0].target).to eq("rfc")
      expect(elem.processing_instructions[0].content).to eq('strict="yes"')
      expect(elem.processing_instructions[1].target).to eq("rfc")
      expect(elem.processing_instructions[1].content).to eq('compact="yes"')
    end
  end

  describe "map_processing_instruction DSL" do
    before do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it "serializes hash attribute as processing instructions" do
      doc_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :pi_settings, :hash

        xml do
          root "rfc"
          map_element "title", to: :title
          map_processing_instruction "rfc", to: :pi_settings
        end
      end

      doc = doc_class.new(
        title: "Test RFC",
        pi_settings: { "strict" => "yes", "compact" => "yes" },
      )

      xml = doc.to_xml(declaration: true)

      expect(xml).to include('<?rfc strict="yes"?>')
      expect(xml).to include('<?rfc compact="yes"?>')
      expect(xml).to include("<title>Test RFC</title>")
      expect(xml).to include("<rfc>")
    end

    it "serializes nil pi_settings without errors (no PIs emitted)" do
      doc_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :pi_settings, :hash

        xml do
          root "rfc"
          map_element "title", to: :title
          map_processing_instruction "rfc", to: :pi_settings
        end
      end

      doc = doc_class.new(title: "Test RFC", pi_settings: nil)
      xml = doc.to_xml(declaration: true)

      expect(xml).not_to include("<?rfc")
      expect(xml).to include("<title>Test RFC</title>")
    end

    it "handles empty hash pi_settings" do
      doc_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :pi_settings, :hash

        xml do
          root "rfc"
          map_element "title", to: :title
          map_processing_instruction "rfc", to: :pi_settings
        end
      end

      doc = doc_class.new(title: "Test RFC", pi_settings: {})
      xml = doc.to_xml(declaration: true)

      expect(xml).not_to include("<?rfc")
      expect(xml).to include("<title>Test RFC</title>")
    end

    it "supports multiple PI targets" do
      doc_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :rfc_pis, :hash
        attribute :xml_pis, :hash

        xml do
          root "doc"
          map_element "title", to: :title
          map_processing_instruction "rfc", to: :rfc_pis
          map_processing_instruction "xml-stylesheet", to: :xml_pis
        end
      end

      doc = doc_class.new(
        title: "Multi PI",
        rfc_pis: { "strict" => "yes" },
        xml_pis: { "href" => "style.xsl" },
      )
      xml = doc.to_xml(declaration: true)

      expect(xml).to include('<?rfc strict="yes"?>')
      expect(xml).to include('<?xml-stylesheet href="style.xsl"?>')
    end

    it "skips nil values in pi_settings hash" do
      doc_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :pi_settings, :hash

        xml do
          root "rfc"
          map_element "title", to: :title
          map_processing_instruction "rfc", to: :pi_settings
        end
      end

      doc = doc_class.new(
        title: "Test",
        pi_settings: { "strict" => "yes", "compact" => nil },
      )
      xml = doc.to_xml(declaration: true)

      expect(xml).to include('<?rfc strict="yes"?>')
      expect(xml).not_to include("compact")
    end
  end

  describe "Manual PI injection via transform" do
    it "adds PIs to the root XmlElement and serializes them" do
      doc_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string

        xml do
          root "doc"
          map_element "title", to: :title
        end
      end

      doc = doc_class.new(title: "Test")

      transformation = doc_class.transformation_for(:xml)
      xml_element = transformation.transform(doc, {})

      xml_element.add_processing_instruction("rfc", 'strict="yes"')
      xml_element.add_processing_instruction("rfc", 'compact="yes"')

      adapter = Lutaml::Xml::Adapter::NokogiriAdapter.new(xml_element)
      xml = adapter.to_xml(mapper_class: doc_class, declaration: true)

      expect(xml).to include('<?rfc strict="yes"?>')
      expect(xml).to include('<?rfc compact="yes"?>')
      expect(xml).to include("<title>Test</title>")
    end
  end

  describe "ProcessingInstructionMapping" do
    it "stores target and to" do
      mapping = Lutaml::Xml::ProcessingInstructionMapping.new("rfc",
                                                              :pi_settings)
      expect(mapping.target).to eq("rfc")
      expect(mapping.to).to eq(:pi_settings)
    end

    it "duplicates correctly" do
      mapping = Lutaml::Xml::ProcessingInstructionMapping.new("rfc",
                                                              :pi_settings)
      dup = mapping.dup
      expect(dup.target).to eq("rfc")
      expect(dup.to).to eq(:pi_settings)
      expect(dup.object_id).not_to eq(mapping.object_id)
    end
  end

  describe "Mapping deep_dup with PI mappings" do
    it "copies processing_instruction_mappings in deep_dup" do
      mapping = Lutaml::Xml::Mapping.new
      mapping.root "rfc"
      mapping.map_processing_instruction "rfc", to: :pi_settings

      dup = mapping.deep_dup
      dup_pis = dup.processing_instruction_mappings
      expect(dup_pis.length).to eq(1)
      expect(dup_pis[0].target).to eq("rfc")
      expect(dup_pis[0].to).to eq(:pi_settings)
      expect(dup_pis[0].object_id).not_to eq(mapping.processing_instruction_mappings[0].object_id)
    end
  end

  describe "parse_pseudo_attributes" do
    let(:pi_class) { Lutaml::Xml::DataModel::XmlProcessingInstruction }

    it "parses a single pseudo-attribute" do
      result = pi_class.parse_pseudo_attributes('strict="yes"')
      expect(result).to eq({ "strict" => "yes" })
    end

    it "parses multiple pseudo-attributes" do
      result = pi_class.parse_pseudo_attributes('toc="yes" oxy-markup="no"')
      expect(result).to eq({ "toc" => "yes", "oxy-markup" => "no" })
    end

    it "returns empty hash for blank content" do
      expect(pi_class.parse_pseudo_attributes("")).to eq({})
      expect(pi_class.parse_pseudo_attributes(nil)).to eq({})
    end

    it "handles single-quoted values" do
      result = pi_class.parse_pseudo_attributes("strict='yes'")
      expect(result).to eq({ "strict" => "yes" })
    end
  end

  describe "Round-trip (from_xml → to_xml)" do
    shared_examples "PI round-trip behavior" do |adapter_class|
      around do |example|
        old_adapter = Lutaml::Model::Config.xml_adapter
        Lutaml::Model::Config.xml_adapter = adapter_class
        example.run
      ensure
        Lutaml::Model::Config.xml_adapter = old_adapter
      end

      it "round-trips hash PI settings" do
        doc_class = Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string
          attribute :pi_settings, :hash

          xml do
            root "rfc"
            map_element "title", to: :title
            map_processing_instruction "rfc", to: :pi_settings
          end
        end

        original = <<~XML
          <?rfc strict="yes"?>
          <?rfc compact="no"?>
          <rfc><title>Test RFC</title></rfc>
        XML

        doc = doc_class.from_xml(original)
        expect(doc.pi_settings).to eq({ "strict" => "yes", "compact" => "no" })
        expect(doc.title).to eq("Test RFC")

        xml = doc.to_xml(declaration: true)
        expect(xml).to include('<?rfc strict="yes"?>')
        expect(xml).to include('<?rfc compact="no"?>')
        expect(xml).to include("<title>Test RFC</title>")
      end

      it "round-trips with no PIs present leaving attribute at default" do
        doc_class = Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string
          attribute :pi_settings, :hash

          xml do
            root "rfc"
            map_element "title", to: :title
            map_processing_instruction "rfc", to: :pi_settings
          end
        end

        doc = doc_class.from_xml("<rfc><title>No PIs</title></rfc>")
        expect(doc.using_default?(:pi_settings)).to be true
        expect(doc.title).to eq("No PIs")
      end

      it "round-trips multiple PI targets" do
        doc_class = Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string
          attribute :rfc_pis, :hash
          attribute :stylesheet_pis, :hash

          xml do
            root "doc"
            map_element "title", to: :title
            map_processing_instruction "rfc", to: :rfc_pis
            map_processing_instruction "xml-stylesheet", to: :stylesheet_pis
          end
        end

        original = <<~XML
          <?rfc strict="yes"?>
          <?xml-stylesheet href="style.xsl"?>
          <doc><title>Multi</title></doc>
        XML

        doc = doc_class.from_xml(original)
        expect(doc.rfc_pis).to eq({ "strict" => "yes" })
        expect(doc.stylesheet_pis).to eq({ "href" => "style.xsl" })

        xml = doc.to_xml(declaration: true)
        expect(xml).to include('<?rfc strict="yes"?>')
        expect(xml).to include('<?xml-stylesheet href="style.xsl"?>')
      end

      it "round-trips PI with multiple pseudo-attributes into merged hash" do
        doc_class = Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string
          attribute :db_pis, :hash

          xml do
            root "book"
            map_element "title", to: :title
            map_processing_instruction "db", to: :db_pis
          end
        end

        original = <<~XML
          <?db toc="yes" oxy-markup="no"?>
          <book><title>DocBook Test</title></book>
        XML

        doc = doc_class.from_xml(original)
        expect(doc.db_pis).to eq({ "toc" => "yes", "oxy-markup" => "no" })
      end

      it "round-trips Array-mode PI attribute" do
        doc_class = Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string
          attribute :rfc_pis, :string, collection: true

          xml do
            root "rfc"
            map_element "title", to: :title
            map_processing_instruction "rfc", to: :rfc_pis
          end
        end

        original = <<~XML
          <?rfc strict="yes"?>
          <?rfc compact="no"?>
          <rfc><title>Array Mode</title></rfc>
        XML

        doc = doc_class.from_xml(original)
        expect(doc.rfc_pis).to eq(['strict="yes"', 'compact="no"'])
      end
    end

    describe Lutaml::Xml::Adapter::NokogiriAdapter do
      it_behaves_like "PI round-trip behavior", described_class
    end

    describe Lutaml::Xml::Adapter::OxAdapter do
      if TestAdapterConfig.adapter_enabled?(:ox)
        it_behaves_like "PI round-trip behavior", described_class
      end
    end

    describe Lutaml::Xml::Adapter::OgaAdapter do
      if TestAdapterConfig.adapter_enabled?(:oga)
        it_behaves_like "PI round-trip behavior", described_class
      end
    end

    describe Lutaml::Xml::Adapter::RexmlAdapter do
      if TestAdapterConfig.adapter_enabled?(:rexml)
        it_behaves_like "PI round-trip behavior", described_class
      end
    end
  end
end
