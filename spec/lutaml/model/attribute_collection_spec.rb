require "spec_helper"
require "lutaml/model"

module AttributeCollection
  class StringParts < Lutaml::Model::Collection
    instances :parts, :string

    def to_s
      parts.join(" -- ")
    end
  end

  class BibliographicItem < Lutaml::Model::Serializable
    attribute :title_parts, :string, collection: StringParts

    xml do
      root "titles"
      map_element "title", to: :title_parts
    end

    key_value do
      root "titles"
      map_instances to: :title_parts
    end

    def render_title
      title_parts.to_s
    end
  end
end

RSpec.describe AttributeCollection do
  let(:xml_data) do
    <<~XML
      <titles>
        <title>Title One</title>
        <title>Title Two</title>
        <title>Title Three</title>
      </titles>
    XML
  end

  let(:yaml_data) do
    <<~YAML
      ---
      titles:
      - Title One
      - Title Two
      - Title Three
    YAML
  end

  describe "BibliographicItem with custom collection" do
    let(:bib_item) { AttributeCollection::BibliographicItem.from_xml(xml_data) }

    it "initializes with custom collection class" do
      expect(bib_item.title_parts).to be_a(AttributeCollection::StringParts)
    end

    it "contains the correct number of title parts" do
      expect(bib_item.title_parts.count).to eq(3)
    end

    it "contains the correct title parts" do
      expect(bib_item.title_parts.parts).to eq(["Title One", "Title Two",
                                                "Title Three"])
    end

    it "renders title with custom separator" do
      expect(bib_item.render_title).to eq("Title One -- Title Two -- Title Three")
    end

    it "serializes to XML correctly" do
      expect(bib_item.to_xml).to be_xml_equivalent_to(xml_data)
    end

    it "deserializes from YAML correctly" do
      yaml_bib_item = AttributeCollection::BibliographicItem.from_yaml(yaml_data)
      expect(yaml_bib_item.title_parts.parts).to eq(["Title One", "Title Two",
                                                     "Title Three"])
    end

    it "serializes to YAML correctly" do
      expect(bib_item.to_yaml.strip).to eq(yaml_data.strip)
    end

    it "can be initialized with an array of strings" do
      bib_item = AttributeCollection::BibliographicItem.new(
        title_parts: AttributeCollection::StringParts.new(
          ["Part One", "Part Two"],
        ),
      )

      expect(bib_item.title_parts.parts).to eq(["Part One", "Part Two"])
    end

    it "can be initialized with a custom collection instance" do
      collection = AttributeCollection::StringParts.new(["Custom One",
                                                         "Custom Two"])
      bib_item = AttributeCollection::BibliographicItem.new(title_parts: collection)
      expect(bib_item.title_parts.parts).to eq(["Custom One", "Custom Two"])
    end
  end
end
