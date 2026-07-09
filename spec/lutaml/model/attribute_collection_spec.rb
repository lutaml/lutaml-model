require "spec_helper"
require_relative "../../../lib/lutaml/model"

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
      element "titles"
      map_element "title", to: :title_parts
    end

    key_value do
      key "titles"
      map_instances to: :title_parts
    end

    def render_title
      title_parts.to_s
    end
  end

  class NestedTitle < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      element "artifact"
      map_element "content", to: :content
    end
  end

  class NestedTitleCollection < Lutaml::Model::Collection
    instances :items, NestedTitle

    xml do
      element "title-group"
      map_element "artifact", to: :items
    end
  end

  class NestedBibliographicItem < Lutaml::Model::Serializable
    attribute :titles, NestedTitleCollection

    xml do
      element "bibitem"
      map_element "titles", to: :titles
    end
  end

  class NestedTitleNamespace < Lutaml::Xml::Namespace
    uri "http://example.com/nested-title"
    uri_aliases "http://example.com/nested-title-alias"
    prefix_default "nt"
  end

  class NamespacedNestedTitle < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      element "artifact"
      namespace NestedTitleNamespace
      map_element "content", to: :content
    end
  end

  class NamespacedNestedTitleCollection < Lutaml::Model::Collection
    instances :items, NamespacedNestedTitle

    xml do
      element "title-group"
      namespace NestedTitleNamespace
      map_element "artifact", to: :items
    end
  end

  class NamespacedNestedBibliographicItem < Lutaml::Model::Serializable
    attribute :titles, NamespacedNestedTitleCollection

    xml do
      element "bibitem"
      map_element "titles", to: :titles
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

  describe "BibliographicItem with nested collection element" do
    let(:nested_xml_data) do
      <<~XML
        <bibitem>
          <titles>
            <title-group>
              <artifact>
                <content>Title One</content>
              </artifact>
              <artifact>
                <content>Title Two</content>
              </artifact>
              <artifact>
                <content>Title Three</content>
              </artifact>
            </title-group>
          </titles>
        </bibitem>
      XML
    end

    it "deserializes the collection from its nested root element" do
      bib_item = AttributeCollection::NestedBibliographicItem.from_xml(
        nested_xml_data,
      )

      expect(bib_item.titles).to be_a(AttributeCollection::NestedTitleCollection)
      expect(bib_item.titles.items.map(&:content)).to eq(
        ["Title One", "Title Two", "Title Three"],
      )
    end

    it "serializes the collection under the mapped parent element" do
      titles = AttributeCollection::NestedTitleCollection.new(
        [
          AttributeCollection::NestedTitle.new(content: "Title One"),
          AttributeCollection::NestedTitle.new(content: "Title Two"),
          AttributeCollection::NestedTitle.new(content: "Title Three"),
        ],
      )
      bib_item = AttributeCollection::NestedBibliographicItem.new(
        titles: titles,
      )

      expect(bib_item.to_xml).to be_xml_equivalent_to(nested_xml_data)
    end

    it "does not unwrap a matching collection root from the wrong namespace" do
      xml = <<~XML
        <bibitem xmlns:nt="http://example.com/nested-title"
                 xmlns:other="http://example.com/other-title">
          <titles>
            <other:title-group>
              <other:artifact>
                <other:content>Wrong namespace</other:content>
              </other:artifact>
            </other:title-group>
            <nt:title-group>
              <nt:artifact>
                <nt:content>Right namespace</nt:content>
              </nt:artifact>
            </nt:title-group>
          </titles>
        </bibitem>
      XML

      bib_item = AttributeCollection::NamespacedNestedBibliographicItem.from_xml(
        xml,
      )

      expect(bib_item.titles.items.map(&:content)).to eq(["Right namespace"])
    end

    it "accepts namespace aliases for the nested collection root" do
      xml = <<~XML
        <bibitem xmlns:alias="http://example.com/nested-title-alias">
          <titles>
            <alias:title-group>
              <alias:artifact>
                <alias:content>Alias namespace</alias:content>
              </alias:artifact>
            </alias:title-group>
          </titles>
        </bibitem>
      XML

      bib_item = AttributeCollection::NamespacedNestedBibliographicItem.from_xml(
        xml,
      )

      expect(bib_item.titles.items.map(&:content)).to eq(["Alias namespace"])
    end
  end
end
