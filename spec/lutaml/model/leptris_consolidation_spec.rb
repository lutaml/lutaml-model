# frozen_string_literal: true

require "spec_helper"

# Reduced from the real IEC rice presentation fixture. The public model DSL
# reproduces its title organization without depending on Metanorma gems.
module LeptrisConsolidationSpec
  class Namespace < Lutaml::Xml::Namespace
    uri "https://www.metanorma.org/ns/standoc"
    prefix_default "standoc"
    element_form_default :qualified
  end

  class Title < Lutaml::Model::Serializable
    attribute :language, :string
    attribute :kind, :string
    attribute :value, :string

    xml do
      element "title"
      namespace Namespace
      map_attribute "language", to: :language
      map_attribute "type", to: :kind
      map_content to: :value
    end
  end

  class LocalizedTitle < Lutaml::Model::Serializable
    attribute :language, :string
    attribute :full, Title
    attribute :intro, Title
    attribute :main, Title
    attribute :part, Title
    attribute :part_prefix, Title
  end

  class Titles < Lutaml::Model::Collection
    instances :items, Title
    organizes :per_language, LocalizedTitle

    xml do
      element "titles"
      namespace Namespace
      map_instances to: :items
      consolidate_map by: :language, to: :per_language do
        gather :language, to: :language
        dispatch_by :kind do
          route "main" => :full
          route "title-intro" => :intro
          route "title-main" => :main
          route "title-part" => :part
          route "title-part-prefix" => :part_prefix
        end
      end
    end
  end

  class Bibdata < Lutaml::Model::Serializable
    attribute :titles, Title, collection: Titles

    xml do
      element "bibdata"
      namespace Namespace
      map_element "title", to: :titles
    end
  end

  class Document < Lutaml::Model::Serializable
    attribute :bibdata, Bibdata

    xml do
      element "metanorma"
      namespace Namespace
      map_element "bibdata", to: :bibdata
    end
  end
end

RSpec.describe "Leptris custom Collection consolidation" do
  around do |example|
    original_adapter = Lutaml::Model::Config.xml_adapter_type
    original_fast = Lutaml::Model::Config.instance.xml_plan_fast_path
    Lutaml::Model::Config.xml_adapter_type = :leptris
    example.run
  ensure
    Lutaml::Model::Config.xml_adapter_type = original_adapter
    Lutaml::Model::Config.instance.xml_plan_fast_path = original_fast
  end

  let(:xml) do
    File.read(File.expand_path("../../fixtures/metanorma_iec_title_consolidation.xml", __dir__))
  end

  [true, false].each do |fast|
    it "organizes real nested title data with xml_plan_fast_path=#{fast}" do
      expect(Lutaml::Xml::Leptris.plan_path_compatible?).to be(true)

      Lutaml::Model::Config.instance.xml_plan_fast_path = fast
      if fast
        plan = Lutaml::Xml::Leptris::PlanCompiler.compile(
          LeptrisConsolidationSpec::Document,
          Lutaml::Model::Config.default_register,
        )
        expect(plan).not_to be_nil # Do not silently test an interpretive fallback.
        allow(Lutaml::Xml::Leptris::PlanHydrator).to receive(:call).and_call_original
      end
      document = LeptrisConsolidationSpec::Document.from_xml(xml)
      if fast
        expect(Lutaml::Xml::Leptris::PlanHydrator).to have_received(:call)
          .with(LeptrisConsolidationSpec::Bibdata, anything, anything, any_args)
      end
      titles = document.bibdata.titles

      expect(titles.items.length).to eq(10)
      expect(titles.per_language.size).to eq(2)
      expect(titles.per_language.map(&:language)).to contain_exactly("en", "fr")
      en = titles.per_language.find { |group| group.language == "en" }
      fr = titles.per_language.find { |group| group.language == "fr" }
      expect(en.full.value).to include("Cereals and pulses")
      expect(en.part.value).to eq("Rice")
      expect(fr.full.value).to include("Céréales et légumineuses")
      expect(fr.part.value).to eq("Riz")
      expect(fr.part_prefix.value).to eq("Partie\u00a01")

      # Re-running post-processing replaces the organized view without
      # duplicating groups or replacing the raw item collection.
      original_items = titles.items.dup
      Lutaml::Xml::CollectionConsolidation.call(document.bibdata, :default)
      expect(titles.items).to eq(original_items)
      expect(titles.per_language.size).to eq(2)
      expect(titles.per_language.find { |group| group.language == "fr" }.part).to equal(fr.part)

      reparsed = LeptrisConsolidationSpec::Document.from_xml(document.to_xml)
      expect(reparsed.bibdata.titles.items.size).to eq(10)
      expect(reparsed.bibdata.titles.per_language.size).to eq(2)
      expect(reparsed.bibdata.titles.per_language.map { |group| group.part.value })
        .to contain_exactly("Rice", "Riz")
    end
  end
end
