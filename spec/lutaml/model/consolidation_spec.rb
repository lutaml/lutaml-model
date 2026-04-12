# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Consolidation Mapping" do
  before do
    Lutaml::Model::GlobalContext.clear_caches
    Lutaml::Model::TransformationRegistry.instance.clear
    Lutaml::Model::GlobalRegister.instance.reset
  end

  describe "Pattern A: Attribute-based consolidation" do
    before do
      # Individual title model
      stub_const("ConTitle", Class.new(Lutaml::Model::Serializable) do
        attribute :lang, :string
        attribute :type_of_title, :string
        attribute :content, :string

        xml do
          root "title"
          map_attribute "lang", to: :lang
          map_attribute "type", to: :type_of_title
          map_content to: :content
        end
      end)

      # Per-language group model
      stub_const("ConPerLangGroup", Class.new(Lutaml::Model::Serializable) do
        attribute :lang, :string
        attribute :main_title, ConTitle
        attribute :title_intro, ConTitle
        attribute :title_main, ConTitle
        attribute :title_part, ConTitle
      end)

      # Title collection with consolidation
      stub_const("ConTitleCollection", Class.new(Lutaml::Model::Collection) do
        instances :items, ConTitle
        organizes :per_lang, ConPerLangGroup

        xml do
          root "titles"
          map_instances to: :items
          consolidate_map by: :lang, to: :per_lang do
            gather :lang, to: :lang
            dispatch_by :type_of_title do
              route "main" => :main_title
              route "title-intro" => :title_intro
              route "title-main" => :title_main
              route "title-part" => :title_part
            end
          end
        end
      end)

      # Parent model
      stub_const("ConBibdata", Class.new(Lutaml::Model::Serializable) do
        attribute :titles, ConTitle, collection: ConTitleCollection

        xml do
          root "bibdata"
          map_element "title", to: :titles
        end
      end)
    end

    let(:xml) do
      <<~XML
        <bibdata>
          <title lang="en" type="main">Cereals and pulses</title>
          <title lang="en" type="title-intro">Cereals and pulses</title>
          <title lang="en" type="title-main">Specifications</title>
          <title lang="en" type="title-part">Rice</title>
          <title lang="fr" type="main">Céréales et légumineuses</title>
          <title lang="fr" type="title-intro">Céréales</title>
          <title lang="fr" type="title-part">Riz</title>
        </bibdata>
      XML
    end

    it "groups titles by language" do
      bibdata = ConBibdata.from_xml(xml)
      collection = bibdata.titles

      expect(collection).to be_a(ConTitleCollection)
      expect(collection.per_lang.size).to eq(2)
    end

    it "assigns language to each group" do
      bibdata = ConBibdata.from_xml(xml)
      langs = bibdata.titles.per_lang.map(&:lang)

      expect(langs).to contain_exactly("en", "fr")
    end

    it "dispatches titles to correct attributes within each group" do
      bibdata = ConBibdata.from_xml(xml)
      en_group = bibdata.titles.per_lang.find { |g| g.lang == "en" }

      expect(en_group.main_title.content).to eq("Cereals and pulses")
      expect(en_group.title_intro.content).to eq("Cereals and pulses")
      expect(en_group.title_main.content).to eq("Specifications")
      expect(en_group.title_part.content).to eq("Rice")
    end

    it "handles groups with different attribute counts" do
      bibdata = ConBibdata.from_xml(xml)
      fr_group = bibdata.titles.per_lang.find { |g| g.lang == "fr" }

      expect(fr_group.main_title.content).to eq("Céréales et légumineuses")
      expect(fr_group.title_intro.content).to eq("Céréales")
      expect(fr_group.title_part.content).to eq("Riz")
      # fr has no title-main
      expect(fr_group.title_main).to be_nil
    end

    it "preserves raw items" do
      bibdata = ConBibdata.from_xml(xml)

      expect(bibdata.titles.items.size).to eq(7)
    end

    it "round-trips through XML serialization" do
      bibdata = ConBibdata.from_xml(xml)
      result = bibdata.to_xml

      reparsed = ConBibdata.from_xml(result)
      en_group = reparsed.titles.per_lang.find { |g| g.lang == "en" }

      expect(en_group.main_title.content).to eq("Cereals and pulses")
      expect(en_group.title_part.content).to eq("Rice")
    end
  end

  describe "Pattern A: Group by type, distribute by language" do
    before do
      stub_const("ConTitle2", Class.new(Lutaml::Model::Serializable) do
        attribute :lang, :string
        attribute :type_of_title, :string
        attribute :content, :string

        xml do
          root "title"
          map_attribute "lang", to: :lang
          map_attribute "type", to: :type_of_title
          map_content to: :content
        end
      end)

      stub_const("ConPerTypeGroup", Class.new(Lutaml::Model::Serializable) do
        attribute :type_of_title, :string
        attribute :en, ConTitle2
        attribute :fr, ConTitle2
      end)

      stub_const("ConTitleCollection2", Class.new(Lutaml::Model::Collection) do
        instances :items, ConTitle2
        organizes :per_type, ConPerTypeGroup

        xml do
          root "titles"
          map_instances to: :items
          consolidate_map by: :type_of_title, to: :per_type do
            gather :type_of_title, to: :type_of_title
            dispatch_by :lang do
              route "en" => :en
              route "fr" => :fr
            end
          end
        end
      end)

      stub_const("ConBibdata2", Class.new(Lutaml::Model::Serializable) do
        attribute :titles, ConTitle2, collection: ConTitleCollection2

        xml do
          root "bibdata"
          map_element "title", to: :titles
        end
      end)
    end

    let(:xml) do
      <<~XML
        <bibdata>
          <title lang="en" type="main">Cereals and pulses</title>
          <title lang="fr" type="main">Céréales et légumineuses</title>
          <title lang="en" type="title-part">Rice</title>
          <title lang="fr" type="title-part">Riz</title>
        </bibdata>
      XML
    end

    it "groups titles by type" do
      bibdata = ConBibdata2.from_xml(xml)
      types = bibdata.titles.per_type.map(&:type_of_title)

      expect(types).to contain_exactly("main", "title-part")
    end

    it "dispatches languages to correct attributes" do
      bibdata = ConBibdata2.from_xml(xml)
      main_group = bibdata.titles.per_type.find do |g|
        g.type_of_title == "main"
      end

      expect(main_group.en.content).to eq("Cereals and pulses")
      expect(main_group.fr.content).to eq("Céréales et légumineuses")
    end
  end

  describe "DSL structure" do
    it "stores organization on Collection class" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      collection_class = Class.new(Lutaml::Model::Collection) do
        organizes :groups, klass
      end

      org = collection_class.organization
      expect(org).to be_a(Lutaml::Model::Organization)
      expect(org.name).to eq(:groups)
      expect(org.group_class).to eq(klass)
    end

    it "creates organized attribute on Collection" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      collection_class = Class.new(Lutaml::Model::Collection) do
        organizes :groups, klass
      end

      expect(collection_class.attributes).to have_key(:groups)
    end

    it "stores consolidation_maps on Xml::Mapping" do
      group_class = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      collection_class = Class.new(Lutaml::Model::Collection) do
        organizes :entries, group_class

        xml do
          root "test"
          consolidate_map by: :lang, to: :entries do
            gather :lang, to: :lang
            dispatch_by :type do
              route "main" => :main
            end
          end
        end
      end

      mapping = collection_class.mappings_for(:xml)
      expect(mapping.consolidation_maps.size).to eq(1)
      map = mapping.consolidation_maps.first
      expect(map.by).to eq(:lang)
      expect(map.to).to eq(:entries)
      expect(map.rules.size).to eq(2)
    end

    it "stores pattern consolidation_maps" do
      entry_class = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :key, :string
        attribute :desc, :string
      end

      collection_class = Class.new(Lutaml::Model::Collection) do
        organizes :entries, entry_class

        xml do
          root "test"
          consolidate_map by: :pattern, to: :entries do
            map_element "member", to: :name
            map_element "member_key", to: :key
            map_content to: :desc
          end
        end
      end

      mapping = collection_class.mappings_for(:xml)
      map = mapping.consolidation_maps.first
      expect(map.pattern?).to be true
      expect(map.attribute_based?).to be false
      expect(map.rules.size).to eq(3)
    end
  end
end
