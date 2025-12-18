require "spec_helper"
require "lutaml/model"

module XmlLangSpec
  class XmlNamespace < Lutaml::Model::XmlNamespace
    uri "http://www.w3.org/XML/1998/namespace"
    prefix_default "xml"
  end

  class ExNamespace < Lutaml::Model::XmlNamespace
    uri "http://example.com/ns"
    prefix_default "ex"
    attribute_form_default :qualified  # Attributes should be prefixed
  end

  class XmlLang < Lutaml::Model::Type::String
    xml_namespace XmlNamespace
  end

  class BasicXmlLangModel < Lutaml::Model::Serializable
    attribute :content, :string
    attribute :lang, XmlLang

    xml do
      element "doc"
      map_element "content", to: :content
      map_attribute "lang", to: :lang
    end
  end

  class XmlSpace < Lutaml::Model::Type::String
    xml_namespace XmlNamespace
  end

  class XmlId < Lutaml::Model::Type::String
    xml_namespace XmlNamespace
  end

  class MultiXmlAttributesModel < Lutaml::Model::Serializable
    attribute :lang, XmlLang
    attribute :space, XmlSpace
    attribute :id, XmlId
    attribute :content, :string

    xml do
      element "element"
      map_attribute "lang", to: :lang
      map_attribute "space", to: :space
      map_attribute "id", to: :id
      map_content to: :content
    end
  end

  class NestedParagraphModel < Lutaml::Model::Serializable
    attribute :lang, XmlLang
    attribute :text, :string

    xml do
      element "p"
      map_attribute "lang", to: :lang
      map_content to: :text
    end
  end

  class NestedXmlLangModel < Lutaml::Model::Serializable
    attribute :lang, XmlLang
    attribute :title, :string
    attribute :paragraph, NestedParagraphModel

    xml do
      element "article"
      map_attribute "lang", to: :lang
      map_element "title", to: :title
      map_element "p", to: :paragraph
    end
  end

  class ExCustomAttr < Lutaml::Model::Type::String
    xml_namespace ExNamespace
  end

  class MixedNamespacesModel < Lutaml::Model::Serializable
    attribute :lang, XmlLang
    attribute :custom_attr, ExCustomAttr
    attribute :content, :string

    xml do
      element "doc"
      namespace ExNamespace
      map_attribute "lang", to: :lang
      map_attribute "attr", to: :custom_attr
      map_content to: :content
    end
  end

  class InheritanceSectionModel < Lutaml::Model::Serializable
    attribute :lang, XmlLang
    attribute :title, :string
    attribute :text, :string

    xml do
      element "section"
      map_attribute "lang", to: :lang
      map_element "title", to: :title
      map_element "text", to: :text
    end
  end

  class ParentLangModel < Lutaml::Model::Serializable
    attribute :lang, XmlLang
    attribute :sections, InheritanceSectionModel, collection: true

    xml do
      element "document"
      map_attribute "lang", to: :lang
      map_element "section", to: :sections
    end
  end

  class EdgeCaseModel < Lutaml::Model::Serializable
    attribute :lang, XmlLang
    attribute :content, :string

    xml do
      element "doc"
      map_attribute "lang", to: :lang
      map_content to: :content
    end
  end

  class CollectionItemModel < Lutaml::Model::Serializable
    attribute :lang, XmlLang
    attribute :name, :string

    xml do
      element "item"
      map_attribute "lang", to: :lang
      map_element "name", to: :name
    end
  end

  class CollectionXmlLangModel < Lutaml::Model::Serializable
    attribute :items, CollectionItemModel, collection: true

    xml do
      element "items"
      map_element "item", to: :items
    end
  end
end

RSpec.describe "xml:lang Attribute Handling" do
  # Ensure adapter is always reset after each example to prevent pollution
  after(:each) do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  describe "Issue #4: xml:lang Attribute Verification" do
    context "basic xml:lang serialization" do

      it "serializes xml:lang with prefix" do
        model = XmlLangSpec::BasicXmlLangModel.new(content: "Hello", lang: "en")
        xml = model.to_xml
        expect(xml).to include('xml:lang="en"')
      end

      it "never declares xmlns:xml namespace" do
        model = XmlLangSpec::BasicXmlLangModel.new(content: "Hello", lang: "en")
        xml = model.to_xml
        expect(xml).not_to include("xmlns:xml=")
      end

      it "preserves xml:lang in round-trip" do
        xml_in = '<doc xml:lang="fr"><content>Bonjour</content></doc>'
        model = XmlLangSpec::BasicXmlLangModel.from_xml(xml_in)
        expect(model.lang).to eq("fr")
        expect(model.content).to eq("Bonjour")

        xml_out = model.to_xml
        expect(xml_out).to include('xml:lang="fr"')
        expect(xml_out).not_to include("xmlns:xml=")
      end

      it "handles different language codes" do
        languages = %w[en fr de es ja zh-CN pt-BR]
        languages.each do |lang_code|
          model = XmlLangSpec::BasicXmlLangModel.new(content: "Test", lang: lang_code)
          xml = model.to_xml
          expect(xml).to include("xml:lang=\"#{lang_code}\"")
        end
      end

      it "handles nil xml:lang (omits attribute)" do
        model = XmlLangSpec::BasicXmlLangModel.new(content: "Hello", lang: nil)
        xml = model.to_xml
        expect(xml).not_to include("xml:lang")
      end
    end

    context "xml:lang at nested elements" do
      it "serializes xml:lang on root and nested elements" do
        para = XmlLangSpec::NestedParagraphModel.new(lang: "fr", text: "Bonjour le monde")
        model = XmlLangSpec::NestedXmlLangModel.new(
          lang: "en",
          title: "Article Title",
          paragraph: para,
        )

        xml = model.to_xml
        expect(xml).to include('xml:lang="en"')
        expect(xml).to include('xml:lang="fr"')
        expect(xml).not_to include("xmlns:xml=")
      end

      it "preserves nested xml:lang in round-trip" do
        xml_in = <<~XML
          <article xml:lang="en">
            <title>Title</title>
            <p xml:lang="fr">Texte français</p>
          </article>
        XML

        model = XmlLangSpec::NestedXmlLangModel.from_xml(xml_in)
        expect(model.lang).to eq("en")
        expect(model.paragraph.lang).to eq("fr")
        expect(model.paragraph.text).to eq("Texte français")

        xml_out = model.to_xml
        expect(xml_out).to include('xml:lang="en"')
        expect(xml_out).to include('xml:lang="fr"')
        expect(xml_out).not_to include("xmlns:xml=")
      end

      it "handles xml:lang only on nested elements" do
        para = XmlLangSpec::NestedParagraphModel.new(lang: "de", text: "Deutscher Text")
        model = XmlLangSpec::NestedXmlLangModel.new(
          title: "Title",
          paragraph: para,
        )

        xml = model.to_xml
        expect(xml).not_to match(/article[^>]*xml:lang/)
        expect(xml).to match(/<p[^>]*xml:lang="de"/)
        expect(xml).not_to include("xmlns:xml=")
      end
    end

    context "xml:lang with other xml: attributes" do
      it "serializes multiple xml: attributes without declaring xmlns:xml" do
        model = XmlLangSpec::MultiXmlAttributesModel.new(
          lang: "en",
          space: "preserve",
          id: "elem1",
          content: "  Text  ",
        )

        xml = model.to_xml
        expect(xml).to include('xml:lang="en"')
        expect(xml).to include('xml:space="preserve"')
        expect(xml).to include('xml:id="elem1"')
        expect(xml).not_to include("xmlns:xml=")
      end

      it "preserves multiple xml: attributes in round-trip" do
        xml_in = '<element xml:lang="fr" xml:space="preserve" xml:id="test">Content</element>'
        model = XmlLangSpec::MultiXmlAttributesModel.from_xml(xml_in)
        expect(model.lang).to eq("fr")
        expect(model.space).to eq("preserve")
        expect(model.id).to eq("test")

        xml_out = model.to_xml
        expect(xml_out).to include('xml:lang="fr"')
        expect(xml_out).to include('xml:space="preserve"')
        expect(xml_out).to include('xml:id="test"')
        expect(xml_out).not_to include("xmlns:xml=")
      end
    end

    context "xml:lang with custom namespaces" do
      it "distinguishes xml:lang from custom namespace attributes" do
        model = XmlLangSpec::MixedNamespacesModel.new(
          lang: "en",
          custom_attr: "value",
          content: "Text",
        )

        xml = model.to_xml
        expect(xml).to include('xml:lang="en"')
        expect(xml).to include('ex:attr="value"')
        expect(xml).to include('xmlns:ex="http://example.com/ns"')
        expect(xml).not_to include("xmlns:xml=")
      end

      it "preserves both xml:lang and custom namespace in round-trip" do
        xml_in = '<ex:doc xmlns:ex="http://example.com/ns" xml:lang="de" ex:attr="test">Content</ex:doc>'
        model = XmlLangSpec::MixedNamespacesModel.from_xml(xml_in)
        expect(model.lang).to eq("de")
        expect(model.custom_attr).to eq("test")

        xml_out = model.to_xml
        expect(xml_out).to include('xml:lang="de"')
        expect(xml_out).to include('ex:attr="test"')
        expect(xml_out).not_to include("xmlns:xml=")
      end
    end

    context "xml:lang inheritance and overriding" do
      it "allows child elements to override parent xml:lang" do
        section1 = XmlLangSpec::InheritanceSectionModel.new(lang: "fr", title: "Titre", text: "Texte")
        section2 = XmlLangSpec::InheritanceSectionModel.new(title: "Title", text: "Text")
        model = XmlLangSpec::ParentLangModel.new(
          lang: "en",
          sections: [section1, section2],
        )

        xml = model.to_xml
        # Parent has xml:lang="en"
        expect(xml).to match(/<document[^>]*xml:lang="en"/)
        # First section overrides with xml:lang="fr"
        expect(xml).to match(/<section[^>]*xml:lang="fr"/)
        # Second section should not have xml:lang (inherits from parent)
        sections = xml.scan(/<section[^>]*>/)
        expect(sections[1]).not_to include("xml:lang")
      end

      it "preserves xml:lang inheritance in round-trip" do
        xml_in = <<~XML
          <document xml:lang="en">
            <section xml:lang="de">
              <title>Titel</title>
              <text>Text</text>
            </section>
            <section>
              <title>Title</title>
              <text>Text</text>
            </section>
          </document>
        XML

        model = XmlLangSpec::ParentLangModel.from_xml(xml_in)
        expect(model.lang).to eq("en")
        expect(model.sections[0].lang).to eq("de")
        expect(model.sections[1].lang).to be_nil

        xml_out = model.to_xml
        expect(xml_out).to match(/<document[^>]*xml:lang="en"/)
        expect(xml_out).to match(/<section[^>]*xml:lang="de"/)
        expect(xml_out).not_to include("xmlns:xml=")
      end
    end

    context "edge cases" do
      it "handles empty string xml:lang (omits attribute)" do
        model = XmlLangSpec::EdgeCaseModel.new(lang: "", content: "Text")
        xml = model.to_xml
        # Empty string is treated as no value, so attribute is omitted
        expect(xml).not_to include("xml:lang")
      end

      it "handles xml:lang with special characters in language codes" do
        # Language codes can include hyphens, like "zh-Hans-CN"
        model = XmlLangSpec::EdgeCaseModel.new(lang: "zh-Hans-CN", content: "Text")
        xml = model.to_xml
        expect(xml).to include('xml:lang="zh-Hans-CN"')

        parsed = XmlLangSpec::EdgeCaseModel.from_xml(xml)
        expect(parsed.lang).to eq("zh-Hans-CN")
      end

      it "preserves xml:lang with XML entities in content" do
        model = XmlLangSpec::EdgeCaseModel.new(lang: "en", content: "Text with &amp; entity")
        xml = model.to_xml
        expect(xml).to include('xml:lang="en"')
        expect(xml).not_to include("xmlns:xml=")

        parsed = XmlLangSpec::EdgeCaseModel.from_xml(xml)
        expect(parsed.lang).to eq("en")
      end

      it "handles round-trip with xml:lang and XML declaration" do
        xml_in = '<?xml version="1.0" encoding="UTF-8"?><doc xml:lang="en">Text</doc>'
        model = XmlLangSpec::EdgeCaseModel.from_xml(xml_in)
        expect(model.lang).to eq("en")

        xml_out = model.to_xml(declaration: true)
        expect(xml_out).to include('xml:lang="en"')
        expect(xml_out).not_to include("xmlns:xml=")
      end
    end

    context "xml:lang with collections" do
      it "serializes xml:lang on collection items without xmlns:xml" do
        items = [
          XmlLangSpec::CollectionItemModel.new(lang: "en", name: "English"),
          XmlLangSpec::CollectionItemModel.new(lang: "fr", name: "French"),
          XmlLangSpec::CollectionItemModel.new(lang: "de", name: "German"),
        ]
        model = XmlLangSpec::CollectionXmlLangModel.new(items: items)

        xml = model.to_xml
        expect(xml.scan(/xml:lang="en"/).length).to eq(1)
        expect(xml.scan(/xml:lang="fr"/).length).to eq(1)
        expect(xml.scan(/xml:lang="de"/).length).to eq(1)
        expect(xml).not_to include("xmlns:xml=")
      end

      it "preserves xml:lang on all collection items in round-trip" do
        xml_in = <<~XML
          <items>
            <item xml:lang="en"><name>English</name></item>
            <item xml:lang="fr"><name>French</name></item>
            <item xml:lang="de"><name>German</name></item>
          </items>
        XML

        model = XmlLangSpec::CollectionXmlLangModel.from_xml(xml_in)
        expect(model.items.map(&:lang)).to eq(%w[en fr de])

        xml_out = model.to_xml
        expect(xml_out.scan(/xml:lang="en"/).length).to eq(1)
        expect(xml_out.scan(/xml:lang="fr"/).length).to eq(1)
        expect(xml_out.scan(/xml:lang="de"/).length).to eq(1)
        expect(xml_out).not_to include("xmlns:xml=")
      end
    end
  end
end