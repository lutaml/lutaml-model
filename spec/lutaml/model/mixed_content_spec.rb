# spec/lutaml/model/mixed_content_spec.rb

require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require_relative "../../fixtures/sample_model"
require_relative "../../support/xml_mapping_namespaces"

module MixedContentSpec
  class PlanetaryBody < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :distance_from_earth, :integer
    xml do
      element "PlanetaryBody"
      map_element "Name", to: :name
      map_element "DistanceFromEarth", to: :distance_from_earth
    end
  end

  class Source < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      element "source"
      map_content to: :content
    end
  end

  class ElementCitation < Lutaml::Model::Serializable
    attribute :source, Source

    xml do
      element "element-citation"
      map_element "source", to: :source
    end
  end

  class Ref < Lutaml::Model::Serializable
    attribute :element_citation, ElementCitation

    xml do
      element "ref"
      map_element "element-citation", to: :element_citation
    end
  end

  class RefList < Lutaml::Model::Serializable
    attribute :ref, Ref

    xml do
      element "ref-list"
      map_element "ref", to: :ref
    end
  end

  class Back < Lutaml::Model::Serializable
    attribute :ref_list, RefList

    xml do
      element "back"
      map_element "ref-list", to: :ref_list
    end
  end

  class Article < Lutaml::Model::Serializable
    attribute :back, Back

    xml do
      element "article"
      map_element "back", to: :back
    end
  end

  class Latin < Lutaml::Model::Serializable
    attribute :the, :string
    attribute :from, :string
    attribute :heading, :string

    xml do
      element "note"
      map_element "to", to: :the
      map_element "from", to: :from
      map_element "heading", to: :heading
    end
  end

  class Shift < Lutaml::Model::Serializable
    attribute :field, :string, collection: true

    xml do
      element "root"
      map_element "FieldName", to: :field
    end
  end

  class SpecialCharContentWithMixedTrue < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      element "SpecialCharContentWithMixedTrue"
      mixed_content
      map_content to: :content
    end
  end

  class SpecialCharContentWithRawAndMixedOption < Lutaml::Model::Serializable
    attribute :special, :string, raw: true

    xml do
      element "SpecialCharContentWithRawOptionAndMixedOption"
      mixed_content
      map_element :special, to: :special
    end
  end

  class RootMixedContent < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :bold, :string, collection: true
    attribute :italic, :string, collection: true
    attribute :underline, :string
    attribute :content, :string

    xml do
      element "RootMixedContent"
      mixed_content
      map_attribute :id, to: :id
      map_element :bold, to: :bold
      map_element :italic, to: :italic
      map_element :underline, to: :underline
      map_content to: :content
    end
  end

  class RootMixedContentWithModel < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :bold, :string, collection: true
    attribute :italic, :string, collection: true
    attribute :underline, :string
    attribute :planetary_body, PlanetaryBody
    attribute :content, :string

    xml do
      element "RootMixedContentWithModel"
      mixed_content
      map_content to: :content
      map_attribute :id, to: :id
      map_element :bold, to: :bold
      map_element :italic, to: :italic
      map_element :underline, to: :underline
      map_element "PlanetaryBody", to: :planetary_body
    end
  end

  class RootMixedContentNested < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :text, :string
    attribute :content, RootMixedContent
    attribute :sup, :string, collection: true
    attribute :sub, :string, collection: true

    xml do
      element "RootMixedContentNested"
      mixed_content
      map_content to: :text
      map_attribute :id, to: :id
      map_element :sup, to: :sup
      map_element :sub, to: :sub
      map_element "MixedContent", to: :content
    end
  end

  class RootMixedContentNestedWithModel < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :text, :string
    attribute :content, RootMixedContentWithModel
    attribute :sup, :string, collection: true
    attribute :sub, :string, collection: true

    xml do
      element "RootMixedContentNestedWithModel"
      mixed_content

      map_content to: :text
      map_attribute :id, to: :id
      map_element :sup, to: :sup
      map_element :sub, to: :sub
      map_element "MixedContentWithModel", to: :content
    end
  end

  class TextualSupport < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "TextualSupport"

      map_element :value, to: :value
    end
  end

  class HexCode < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      element "HexCode"
      map_content to: :content
    end
  end

  module PrefixedElements
    class Annotation < Lutaml::Model::Serializable
      attribute :content, :string

      xml do
        element "annotation"
        namespace ExampleSchemaNamespace

        map_content to: :content
      end
    end

    class Element < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :status, :string
      attribute :annotation, Annotation

      xml do
        element "element"
        mixed_content

        namespace ExampleSchemaNamespace

        map_attribute :name, to: :name
        map_attribute :status, to: :status
        map_element :annotation, to: :annotation
      end
    end

    class Schema < Lutaml::Model::Serializable
      attribute :element, Element, collection: true

      xml do
        element "schema"
        namespace ExampleSchemaNamespace

        map_element :element, to: :element
      end
    end
  end
end

RSpec.describe "MixedContent" do
  shared_examples "mixed content behavior" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    context "when mixed: true is set at root" do
      let(:xml) do
        <<~XML
          <RootMixedContent id="123">
            The Earth's Moon rings like a <bold>bell</bold> when struck by
            meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
            its surface is covered in <underline>craters</underline>.
            Ain't that <bold>cool</bold>?
          </RootMixedContent>
        XML
      end

      it "deserializes and serializes mixed content correctly" do
        parsed = MixedContentSpec::RootMixedContent.from_xml(xml)

        expected_content = [
          "\n  The Earth's Moon rings like a ",
          " when struck by\n  meteroids. Distanced from the Earth by ",
          ",\n  its surface is covered in ",
          ".\n  Ain't that ",
          "?\n",
        ]

        expect(parsed.id).to eq("123")
        expect(parsed.bold).to eq(["bell", "cool"])
        expect(parsed.italic).to eq(["384,400 km"])
        expect(parsed.underline).to eq("craters")

        parsed.content.each_with_index do |content, index|
          expected_output = expected_content[index]

          # due to the difference in capturing
          # newlines in ox and nokogiri adapters
          if adapter_class == Lutaml::Model::Xml::OxAdapter
            expected_output = expected_output.gsub(/\n\s*/, " ")
          end

          expect(content).to eq(expected_output)
        end

        serialized = parsed.to_xml

        # Ox normalizes whitespace in mixed content per XML spec (semantically equivalent)
        # Canon can't compare whitespace-normalized XML, so we normalize both sides for Ox
        if adapter_class == Lutaml::Model::Xml::OxAdapter
          normalize = ->(str) { str.gsub(/\s+/, ' ').gsub(/\s*</, '<').gsub(/>\s*/, '>').strip }
          expect(normalize.call(serialized)).to eq(normalize.call(xml))
        else
          expect(serialized).to be_xml_equivalent_to(xml)
        end
      end
    end

    context "when mixed: true is set at root with nested model" do
      let(:xml) do
        <<~XML
          <RootMixedContentWithModel id="123">
            The Earth's Moon rings like a <bold>bell</bold> when struck by
            meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
            its surface is covered in <underline>craters</underline>.
            Ain't that <bold>cool</bold>?
            <PlanetaryBody>
              <Name>Moon</Name>
              <DistanceFromEarth>384400</DistanceFromEarth>
            </PlanetaryBody>
            NOTE: The above model content is to be formatted as a table.
          </RootMixedContentWithModel>
        XML
      end

      it "deserializes and serializes mixed content correctly" do
        parsed = MixedContentSpec::RootMixedContentWithModel.from_xml(xml)

        expected_content = [
          "\n  The Earth's Moon rings like a ",
          " when struck by\n  meteroids. Distanced from the Earth by ",
          ",\n  its surface is covered in ",
          ".\n  Ain't that ",
          "?\n  ",
          "\n  NOTE: The above model content is to be formatted as a table.\n",
        ]

        expect(parsed.id).to eq("123")
        expect(parsed.bold).to eq(["bell", "cool"])
        expect(parsed.italic).to eq(["384,400 km"])
        expect(parsed.underline).to eq("craters")

        parsed.content.each_with_index do |content, index|
          expected_output = expected_content[index]

          # due to the difference in capturing
          # newlines in ox and nokogiri adapters
          if adapter_class == Lutaml::Model::Xml::OxAdapter
            expected_output = expected_output.gsub(/\n\s*/, " ")
          end

          expect(content).to eq(expected_output)
        end

        expect(parsed.planetary_body.name).to eq("Moon")
        expect(parsed.planetary_body.distance_from_earth).to eq(384400)

        serialized = parsed.to_xml

        # Ox normalizes whitespace in mixed content per XML spec (semantically equivalent)
        # Canon can't compare whitespace-normalized XML, so we normalize both sides for Ox
        if adapter_class == Lutaml::Model::Xml::OxAdapter
          normalize = ->(str) { str.gsub(/\s+/, ' ').gsub(/\s*</, '<').gsub(/>\s*/, '>').strip }
          expect(normalize.call(serialized)).to eq(normalize.call(xml))
        else
          expect(serialized).to be_xml_equivalent_to(xml)
        end
      end
    end

    context "when mixed: true is set for nested content" do
      let(:xml) do
        <<~XML
          <RootMixedContentNested id="outer123">
            The following text is about the Moon.
            <MixedContent id="inner456">
              The Earth's Moon rings like a <bold>bell</bold> when struck by
              meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
              its surface is covered in <underline>craters</underline>.
              Ain't that <bold>cool</bold>?
            </MixedContent>
            <sup>1</sup>: The Moon is not a planet.
            <sup>2</sup>: The Moon's atmosphere is mainly composed of helium in the form of He<sub>2</sub>.
          </RootMixedContentNested>
        XML
      end

      it "deserializes and serializes mixed content correctly" do
        parsed = MixedContentSpec::RootMixedContentNested.from_xml(xml)

        expected_content = [
          "\n    The Earth's Moon rings like a ",
          " when struck by\n    meteroids. Distanced from the Earth by ",
          ",\n    its surface is covered in ",
          ".\n    Ain't that ",
          "?\n  ",
        ]

        expect(parsed.id).to eq("outer123")
        expect(parsed.sup).to eq(["1", "2"])
        expect(parsed.sub).to eq(["2"])
        expect(parsed.content.id).to eq("inner456")
        expect(parsed.content.bold).to eq(["bell", "cool"])
        expect(parsed.content.italic).to eq(["384,400 km"])
        expect(parsed.content.underline).to eq("craters")

        parsed.content.content.each_with_index do |content, index|
          expected_output = expected_content[index]

          # due to the difference in capturing
          # newlines in ox and nokogiri adapters
          if adapter_class == Lutaml::Model::Xml::OxAdapter
            expected_output = expected_output.gsub(/\n\s*/, " ")
          end

          expect(content).to eq(expected_output)
        end
        serialized = parsed.to_xml

        # Ox normalizes whitespace in mixed content per XML spec (semantically equivalent)
        # Canon can't compare whitespace-normalized XML, so we normalize both sides for Ox
        if adapter_class == Lutaml::Model::Xml::OxAdapter
          normalize = ->(str) { str.gsub(/\s+/, ' ').gsub(/\s*</, '<').gsub(/>\s*/, '>').strip }
          expect(normalize.call(serialized)).to eq(normalize.call(xml))
        else
          expect(serialized).to be_xml_equivalent_to(xml)
        end
      end
    end

    context "when mixed: true is set for nested content with model" do
      let(:xml) do
        <<~XML
          <RootMixedContentNestedWithModel id="outer123">
            The following text is about the Moon.
            <MixedContentWithModel id="inner456">
              The Earth's Moon rings like a <bold>bell</bold> when struck by
              meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
              its surface is covered in <underline>craters</underline>.
              Ain't that <bold>cool</bold>?
              <PlanetaryBody>
                <Name>Moon</Name>
                <DistanceFromEarth>384400</DistanceFromEarth>
              </PlanetaryBody>
              NOTE: The above model content is to be formatted as a table.
            </MixedContentWithModel>
            <sup>1</sup>: The Moon is not a planet.
            <sup>2</sup>: The Moon's atmosphere is mainly composed of helium in the form of He<sub>2</sub>.
          </RootMixedContentNestedWithModel>
        XML
      end

      it "deserializes and serializes mixed content correctly" do
        parsed = MixedContentSpec::RootMixedContentNestedWithModel.from_xml(xml)

        expected_content = [
          "\n    The Earth's Moon rings like a ",
          " when struck by\n    meteroids. Distanced from the Earth by ",
          ",\n    its surface is covered in ",
          ".\n    Ain't that ",
          "?\n    ",
          "\n    NOTE: The above model content is to be formatted as a table.\n  ",
        ]

        expect(parsed.id).to eq("outer123")
        expect(parsed.sup).to eq(["1", "2"])
        expect(parsed.sub).to eq(["2"])
        expect(parsed.content.id).to eq("inner456")
        expect(parsed.content.bold).to eq(["bell", "cool"])
        expect(parsed.content.italic).to eq(["384,400 km"])
        expect(parsed.content.underline).to eq("craters")

        parsed.content.content.each_with_index do |content, index|
          expected_output = expected_content[index]

          # due to the difference in capturing
          # newlines in ox and nokogiri adapters
          if adapter_class == Lutaml::Model::Xml::OxAdapter
            expected_output = expected_output.gsub(/\n\s*/, " ")
          end

          expect(content).to eq(expected_output)
        end

        expect(parsed.content.planetary_body.name).to eq("Moon")
        expect(parsed.content.planetary_body.distance_from_earth).to eq(384400)

        serialized = parsed.to_xml

        # Ox normalizes whitespace in mixed content per XML spec (semantically equivalent)
        # Canon can't compare whitespace-normalized XML, so we normalize both sides for Ox
        if adapter_class == Lutaml::Model::Xml::OxAdapter
          normalize = ->(str) { str.gsub(/\s+/, ' ').gsub(/\s*</, '<').gsub(/>\s*/, '>').strip }
          expect(normalize.call(serialized)).to eq(normalize.call(xml))
        else
          expect(serialized).to be_xml_equivalent_to(xml)
        end
      end
    end

    context "when mixed: true is used with map_element" do
      it "raises an error" do
        expect do
          Class.new(Lutaml::Model::Serializable) do
            attribute :id, :string

            xml do
              element "Invalid"
              map_element :id, to: :id, mixed: true
            end
          end
        end.to raise_error(ArgumentError, /unknown keyword: :mixed/)
      end
    end

    context "when mixed: true is used with map_attribute" do
      it "raises an error" do
        expect do
          Class.new(Lutaml::Model::Serializable) do
            attribute :id, :string

            xml do
              element "Invalid"
              map_attribute :id, to: :id, mixed: true
            end
          end
        end.to raise_error(ArgumentError, /unknown keyword: :mixed/)
      end
    end

    context "when special char used in content with mixed true" do
      let(:xml) do
        <<~XML
          <SpecialCharContentWithMixedTrue>
            Moon&#x0026;Mars Distanced&#x00A9;its &#8212; surface covered &amp; processed
          </SpecialCharContentWithMixedTrue>
        XML
      end

      describe ".from_xml" do
        let(:expected_content) do
          "Moon&Mars Distanced©its — surface covered & processed"
        end

        it "deserializes special char mixed content correctly" do
          parsed = MixedContentSpec::SpecialCharContentWithMixedTrue.from_xml(xml)
          expect(parsed.content.strip).to eq(expected_content)
        end
      end

      describe ".to_xml" do
        let(:expected_xml) do
          "Moon&amp;Mars Distanced©its — surface covered &amp; processed"
        end

        it "serializes special char mixed content correctly" do
          parsed = MixedContentSpec::SpecialCharContentWithMixedTrue.from_xml(xml)
          serialized = parsed.to_xml(encoding: "UTF-8")

          expect(serialized).to include(expected_xml)
        end
      end
    end

    context "when special char used in content read from xml file" do
      let(:fixture) { File.read(fixture_path("xml/special_char.xml")) }

      describe ".from_xml" do
        it "deserializes special char mixed content correctly" do
          parsed = MixedContentSpec::Article.from_xml(fixture)
          expect(parsed.back.ref_list.ref.element_citation.source.content).to include("R&D")
        end
      end

      describe ".to_xml" do
        it "serializes special char mixed content correctly" do
          parsed = MixedContentSpec::Article.from_xml(fixture)
          serialized = parsed.to_xml

          expect(serialized).to include("R&amp;D")
        end
      end
    end

    context "when special char entities used with raw true" do
      let(:xml) do
        <<~XML
          <SpecialCharContentWithRawAndMixedOption>
            <special>
              B <p>R&#x0026;C</p>
              C <p>J&#8212;C</p>
              O <p>A &amp; B </p>
              F <p>Z &#x00A9;S</p>
            </special>
          </SpecialCharContentWithRawAndMixedOption>
        XML
      end

      describe ".from_xml" do
        let(:expected_nokogiri_content) do
          "B <p>R&amp;C</p>\n    C <p>J&#x2014;C</p>\n    O <p>A &amp; B </p>\n    F <p>Z &#xA9;S</p>"
        end
        let(:expected_ox_content) do
          "B <p>R&amp;C</p> C <p>J—C</p> O <p>A &amp; B </p> F <p>Z ©S</p>"
        end
        let(:expected_oga_content) do
          "B <p>R&amp;C</p>\n    C <p>J—C</p>\n    O <p>A &amp; B </p>\n    F <p>Z ©S</p>"
        end

        it "deserializes special char mixed content correctly" do
          parsed = MixedContentSpec::SpecialCharContentWithRawAndMixedOption.from_xml(xml)
          expected_content = public_send(:"expected_#{adapter_class.type}_content")
          parsed.special.force_encoding("UTF-8") unless adapter_class == Lutaml::Model::Xml::NokogiriAdapter

          expect(parsed.special.strip).to eq(expected_content)
        end
      end

      describe ".to_xml" do
        let(:expected_nokogiri_xml) do
          <<~XML
            <SpecialCharContentWithRawOptionAndMixedOption><special>
                B <p>R&amp;C</p>
                C <p>J&#x2014;C</p>
                O <p>A &amp; B </p>
                F <p>Z ©S</p>
              </special></SpecialCharContentWithRawOptionAndMixedOption>
          XML
        end

        let(:expected_ox_xml) do
          <<~XML
            <SpecialCharContentWithRawOptionAndMixedOption>
              <special> B <p>R&amp;C</p>
                C <p>J—C</p>
                O <p>A &amp; B </p>
                F <p>Z ©S</p>
              </special>
              </SpecialCharContentWithRawOptionAndMixedOption>
          XML
        end

        let(:expected_oga_xml) do
          <<~XML
            <SpecialCharContentWithRawOptionAndMixedOption>
              <special> B <p>R&amp;C</p>
                C <p>J—C</p>
                O <p>A &amp; B </p>
                F <p>Z ©S</p>
              </special>
            </SpecialCharContentWithRawOptionAndMixedOption>
          XML
        end

        it "serializes special char mixed content correctly" do
          parsed = MixedContentSpec::SpecialCharContentWithRawAndMixedOption.from_xml(xml)
          serialized = parsed.to_xml

          expected_xml = send(:"expected_#{adapter_class.type}_xml")

          # Ox and Oga normalize whitespace in mixed content per XML spec (semantically equivalent)
          # Canon can't compare whitespace-normalized XML, so we normalize both sides
          if adapter_class == Lutaml::Model::Xml::OxAdapter || adapter_class == Lutaml::Model::Xml::OgaAdapter
            normalize = ->(str) { str.gsub(/\s+/, ' ').gsub(/\s*</, '<').gsub(/>\s*/, '>').strip }
            expect(normalize.call(serialized)).to eq(normalize.call(expected_xml))
          else
            expect(serialized).to be_xml_equivalent_to(expected_xml)
          end
        end
      end
    end

    context "when special char used with raw true, remove & if entity not provided" do
      let(:xml) do
        <<~XML
          <SpecialCharContentWithRawAndMixedOption>
            <special>
              B <p>R&amp;C</p>
            </special>
          </SpecialCharContentWithRawAndMixedOption>
        XML
      end

      describe ".from_xml" do
        let(:expected_nokogiri_content) { "B <p>R&amp;C</p>" }
        let(:expected_ox_content) { "B <p>R&amp;C</p>" }

        it "deserializes special char mixed content correctly" do
          parsed = MixedContentSpec::SpecialCharContentWithRawAndMixedOption.from_xml(xml)

          expected_output = adapter_class == Lutaml::Model::Xml::NokogiriAdapter ? expected_nokogiri_content : expected_ox_content
          expect(parsed.special.strip).to eq(expected_output)
        end
      end

      describe ".to_xml" do
        let(:expected_nokogiri_xml) { "B <p>R&amp;C</p>" }
        let(:expected_ox_xml) { "B <p>R&amp;C</p>" }
        let(:expected_oga_xml) { "B <p>R&amp;C</p>" }

        it "serializes special char mixed content correctly" do
          parsed = MixedContentSpec::SpecialCharContentWithRawAndMixedOption.from_xml(xml)
          serialized = parsed.to_xml

          expect(serialized).to include(send(:"expected_#{adapter_class.type}_xml"))
        end
      end
    end

    context "when special char used as full entities" do
      let(:xml) do
        <<~XML
          <TextualSupport>
            <value>&lt;computer security&gt; type of operation specified by an access right</value>
          </TextualSupport>
        XML
      end

      describe ".from_xml" do
        let(:expected_content) do
          "<computer security> type of operation specified by an access right"
        end

        it "deserializes special char mixed content correctly" do
          parsed = MixedContentSpec::TextualSupport.from_xml(xml)

          expect(parsed.value).to eq(expected_content)
        end
      end

      describe ".to_xml" do
        let(:expected_xml) do
          "<TextualSupport>\n  <value>&lt;computer security&gt; type of operation specified by an access right</value>\n</TextualSupport>"
        end
        let(:expected_oga_xml) do
          "<TextualSupport><value>&lt;computer security&gt; type of operation specified by an access right</value></TextualSupport>"
        end

        it "serializes special char mixed content correctly" do
          parsed = MixedContentSpec::TextualSupport.from_xml(xml)
          serialized = parsed.to_xml
          expect(serialized.strip).to be_xml_equivalent_to(expected_xml.strip)
        end
      end
    end

    context "when special char used as full entities, it persist as entities if no encoding provided" do
      let(:xml) do
        <<~XML
          <HexCode>
            &#x2211;computer security&#x220F; type of &#x200B; operation specified &#xB5; by an access right
          </HexCode>
        XML
      end

      describe ".from_xml" do
        let(:expected_content) do
          "∑computer security∏ type of ​ operation specified µ by an access right"
        end

        it "deserializes special char mixed content correctly" do
          parsed = MixedContentSpec::HexCode.from_xml(xml)

          expect(parsed.content.strip).to eq(expected_content)
        end
      end

      describe ".to_xml" do
        context "when default encoding xml" do
          let(:expected_default_encoding_xml) do
            "∑computer security∏ type of ​ operation specified µ by an access right"
          end

          it "serializes special char mixed content correctly with default encoding: UTF-8" do
            parsed = MixedContentSpec::HexCode.from_xml(xml)
            serialized = parsed.to_xml

            expect(serialized.strip).to include(expected_default_encoding_xml)
          end
        end

        context "when encoding: nil xml" do
          let(:expected_encoding_nil_nokogiri_xml) do
            "&#x2211;computer security&#x220F; type of &#x200B; operation specified &#xB5; by an access right"
          end
          let(:expected_encoding_nil_ox_xml) do
            "<HexCode> \xE2\x88\x91computer security\xE2\x88\x8F type of \xE2\x80\x8B operation specified \xC2\xB5 by an access right </HexCode>\n".force_encoding("ASCII-8BIT")
          end
          let(:expected_encoding_nil_oga_xml) do
            "<HexCode>\n  ∑computer security∏ type of ​ operation specified µ by an access right\n</HexCode>"
          end

          it "serializes special char mixed content correctly with encoding: nil to get hexcode" do
            parsed = MixedContentSpec::HexCode.from_xml(xml, encoding: nil)
            serialized = parsed.to_xml(encoding: nil)

            expected_output = if adapter_class == Lutaml::Model::Xml::NokogiriAdapter
                                expected_encoding_nil_nokogiri_xml
                              elsif adapter_class == Lutaml::Model::Xml::OxAdapter
                                expected_encoding_nil_ox_xml
                              else
                                expected_encoding_nil_oga_xml
                              end

            expect(parsed.encoding).to be_nil
            expect(serialized.strip).to include(expected_output.strip)

            if adapter_class == Lutaml::Model::Xml::OxAdapter
              expect(serialized.encoding.to_s).to eq("ASCII-8BIT")
            else
              expect(serialized.encoding.to_s).to eq("UTF-8")
            end
          end
        end
      end
    end

    context "when use encoding in parsing" do
      context "when use SHIFT-JIS encoding" do
        let(:fixture) do
          File.read(fixture_path("xml/shift_jis.xml"), encoding: "Shift_JIS")
        end

        describe ".from_xml" do
          it "verifies the encoding of file read" do
            expect(fixture.encoding.to_s).to eq("Shift_JIS")
          end

          it "deserializes SHIFT encoded content correctly with explicit encoding option" do
            parsed = MixedContentSpec::Shift.from_xml(fixture,
                                                      encoding: "Shift_JIS")

            expected_content = "手書き英字１"

            expect(parsed.field).to include(expected_content)
          end

          it "deserializes SHIFT encoded content incorrectly without explicit encoding option" do
            parsed = MixedContentSpec::Shift.from_xml(fixture)

            expected_content = "手書き英字１"

            expect(parsed.encoding).to eq("Shift_JIS")
            expect(parsed.field).to include(expected_content)
          end
        end

        describe ".to_xml" do
          it "serializes SHIFT-JIS encoding content correctly reading from file" do
            parsed = MixedContentSpec::Shift.from_xml(fixture,
                                                      encoding: "Shift_JIS")
            serialized = parsed.to_xml
            expected = if adapter_class.type == "oga"
                         fixture.gsub(/\s+/, "")
                       else
                         fixture.strip
                       end
            expect(serialized.strip).to eq(expected)
          end

          it "serializes SHIFT-JIS encoding content correctly reading from string" do
            xml = "<root><FieldName>手書き英字１</FieldName><FieldName>123456</FieldName></root>".encode("Shift_JIS")
            parsed = MixedContentSpec::Shift.from_xml(xml,
                                                      encoding: "Shift_JIS")
            serialized = parsed.to_xml(encoding: "Shift_JIS")

            # Strip XML declaration that declares Shift_JIS encoding before transcoding
            serialized_no_decl = serialized.sub(/^<\?xml.*?\?>\s*/, '')
            xml_no_decl = xml.sub(/^<\?xml.*?\?>\s*/, '')
            expect(serialized_no_decl.encode('UTF-8')).to be_xml_equivalent_to(xml_no_decl.encode('UTF-8'))
          end

          it "serializes SHIFT-JIS content correctly bcz xml.encoding used during parsing" do
            parsed = MixedContentSpec::Shift.from_xml(fixture)
            serialized = parsed.to_xml(encoding: "Shift_JIS")

            expected_content = if adapter_class == Lutaml::Model::Xml::NokogiriAdapter
                                 "<root>\n  <FieldName>手書き英字１</FieldName>\n  <FieldName>123456</FieldName>\n</root>"
                               elsif adapter_class == Lutaml::Model::Xml::OxAdapter
                                 "<root>\n  <FieldName>手書き英字１</FieldName>\n  <FieldName>123456</FieldName>\n</root>"
                               else
                                 "<root><FieldName>手書き英字１</FieldName><FieldName>123456</FieldName></root>"
                               end

            # Strip XML declaration before transcoding
            serialized_no_decl = serialized.sub(/^<\?xml.*?\?>\s*/, '')
            expected_no_decl = expected_content.sub(/^<\?xml.*?\?> */, '')
            expect(serialized_no_decl.encode("UTF-8")).to be_xml_equivalent_to(expected_no_decl.encode("UTF-8"))
          end
        end
      end

      context "when use latin (ISO-8859-1) encoding" do
        let(:fixture) do
          File.read(fixture_path("xml/latin_encoding.xml"), encoding: "ISO-8859-1")
        end

        describe ".from_xml" do
          it "verifies the encoding of file read" do
            expect(fixture.encoding.to_s).to eq("ISO-8859-1")
          end

          it "deserializes latin encoded content correctly" do
            parsed = MixedContentSpec::Latin.from_xml(fixture,
                                                      encoding: "ISO-8859-1")

            expect(parsed.encoding).to eq("ISO-8859-1")
            expect(parsed.the).to eq("José")
            expect(parsed.from).to eq("Müller")
            expect(parsed.heading).to eq("Reminder")
          end

          it "deserializes latin encoded content correctly, bcz xml.encoding used for parsing" do
            parsed = MixedContentSpec::Latin.from_xml(fixture)

            expect(parsed.encoding).to eq("ISO-8859-1")

            expect(parsed.the).to eq("José")
            expect(parsed.from).to eq("Müller")
            expect(parsed.heading).to eq("Reminder")
          end
        end

        describe ".to_xml" do
          it "serializes latin encoded content correctly" do
            parsed = MixedContentSpec::Latin.from_xml(fixture,
                                                      encoding: "ISO-8859-1")
            serialized = parsed.to_xml
            expected_xml = if adapter_class == Lutaml::Model::Xml::OgaAdapter
                             "<note><to>José</to><from>Müller</from><heading>Reminder</heading></note>"
                           else
                             "<note>\n  <to>José</to>\n  <from>Müller</from>\n  <heading>Reminder</heading>\n</note>"
                           end
            expect(serialized.encode("UTF-8").strip).to be_xml_equivalent_to(expected_xml.encode("UTF-8"))
          end
        end
      end
    end

    context "when mixed: true is set for prefixed elements" do
      let(:xml) do
        <<~XML
          <examplecom:schema xmlns:examplecom="http://example.com/schema">
            <examplecom:element>
              <examplecom:annotation>Testing annotation examplecom</examplecom:annotation>
            </examplecom:element>
          </examplecom:schema>
        XML
      end

      let(:serialized) do
        MixedContentSpec::PrefixedElements::Schema.from_xml(xml).to_xml
      end

      it "deserializes and serializes mixed prefixed elements correctly for prefixed elements" do
        # W3C Compliance: Models with namespace use default format by default
        # Input uses prefix format, but output uses default format (semantically equivalent)
        expected_xml = <<~XML
          <schema xmlns="http://example.com/schema">
            <element>
              <annotation>Testing annotation examplecom</annotation>
            </element>
          </schema>
        XML

        expect(serialized).to be_xml_equivalent_to(expected_xml)
      end
    end
  end

  describe Lutaml::Model::Xml::NokogiriAdapter do
    it_behaves_like "mixed content behavior", described_class

    it "raises error when serializes special char content with false encoding: 'ABC'" do
      parsed = MixedContentSpec::HexCode.from_xml("<HexCode>&#x2211;computer security</HexCode>")

      expect do
        parsed.to_xml(encoding: "ABC")
      end.to raise_error(StandardError,
                         "unknown encoding name - ABC")
    end
  end

  describe Lutaml::Model::Xml::OxAdapter do
    it_behaves_like "mixed content behavior", described_class if TestAdapterConfig.adapter_enabled?(:ox)
  end

  describe Lutaml::Model::Xml::OgaAdapter do
    it_behaves_like "mixed content behavior", described_class if TestAdapterConfig.adapter_enabled?(:oga)
  end
end
