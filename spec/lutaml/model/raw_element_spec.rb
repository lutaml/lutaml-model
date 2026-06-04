# frozen_string_literal: true

require "spec_helper"

module RawElementSpec
  class SvgContainer < Lutaml::Model::Serializable
    attribute :svg_data, :string

    xml do
      root "container"
      map_element "svg", to: :svg_data, raw_element: true
    end
  end

  class MathContainer < Lutaml::Model::Serializable
    attribute :formula, :string

    xml do
      root "container"
      map_element "math", to: :formula, raw_element: true
    end
  end

  class MixedContainer < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :embedded, :string

    xml do
      root "container"
      map_element "name", to: :name
      map_element "foreign", to: :embedded, raw_element: true
    end
  end

  class NestedRawContainer < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :embedded, :string

    xml do
      root "container"
      map_element "name", to: :name
      map_element "embedded", to: :embedded, raw_element: true
    end
  end

  class MultiRawContainer < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :svg_data, :string
    attribute :math_data, :string

    xml do
      root "container"
      map_element "name", to: :name
      map_element "svg", to: :svg_data, raw_element: true
      map_element "math", to: :math_data, raw_element: true
    end
  end

  class CollectionRawContainer < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :fragments, :string, collection: true

    xml do
      root "container"
      map_element "name", to: :name
      map_element "fragment", to: :fragments, raw_element: true
    end
  end

  class EmptyRawContainer < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :embedded, :string

    xml do
      root "container"
      map_element "name", to: :name
      map_element "foreign", to: :embedded, raw_element: true
    end
  end

  class NormalContainer < Lutaml::Model::Serializable
    attribute :data, :string

    xml do
      root "container"
      map_element "data", to: :data
    end
  end

  RSpec.describe "map_element raw_element: true" do
    describe "deserialization" do
      describe "foreign namespace element capture" do
        let(:svg_xml) do
          <<~XML
            <container>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
                <rect x="0" y="0" width="100" height="100" fill="red"/>
              </svg>
            </container>
          XML
        end

        it "captures the full SVG element including its own tags" do
          doc = SvgContainer.from_xml(svg_xml)
          expect(doc.svg_data).to include("<svg")
          expect(doc.svg_data).to include("</svg>")
          expect(doc.svg_data).to include("viewBox")
          expect(doc.svg_data).to include("<rect")
        end

        it "preserves SVG namespace attribute" do
          doc = SvgContainer.from_xml(svg_xml)
          expect(doc.svg_data).to include("xmlns=\"http://www.w3.org/2000/svg\"")
        end

        it "preserves child elements" do
          doc = SvgContainer.from_xml(svg_xml)
          expect(doc.svg_data).to include("<rect")
          expect(doc.svg_data).to include("fill=\"red\"")
        end
      end

      describe "non-namespaced element capture" do
        let(:math_xml) do
          "<container><math><mfrac><mi>x</mi><mn>2</mn></mfrac></math></container>"
        end

        it "captures the full element" do
          doc = MathContainer.from_xml(math_xml)
          expect(doc.formula).to include("<math>")
          expect(doc.formula).to include("</math>")
          expect(doc.formula).to include("<mfrac>")
        end
      end

      describe "mixed mapped and raw elements" do
        let(:mixed_xml) do
          <<~XML
            <container>
              <name>test</name>
              <foreign attr="value">
                <child>content</child>
              </foreign>
            </container>
          XML
        end

        it "parses normal elements normally" do
          doc = MixedContainer.from_xml(mixed_xml)
          expect(doc.name).to eq("test")
        end

        it "captures raw elements as full XML" do
          doc = MixedContainer.from_xml(mixed_xml)
          expect(doc.embedded).to include("<foreign")
          expect(doc.embedded).to include("</foreign>")
          expect(doc.embedded).to include("attr=\"value\"")
          expect(doc.embedded).to include("<child>content</child>")
        end
      end

      describe "nested XML in raw element" do
        let(:nested_xml) do
          <<~XML
            <container>
              <name>test</name>
              <embedded>
                <level1>
                  <level2 attr="deep">text</level2>
                </level1>
              </embedded>
            </container>
          XML
        end

        it "preserves full nesting" do
          doc = NestedRawContainer.from_xml(nested_xml)
          expect(doc.embedded).to include("<level1>")
          expect(doc.embedded).to include("<level2 attr=\"deep\">text</level2>")
          expect(doc.embedded).to include("</level1>")
        end
      end

      describe "multiple raw_element mappings" do
        let(:multi_xml) do
          <<~XML
            <container>
              <name>mixed content</name>
              <svg xmlns="http://www.w3.org/2000/svg"><circle r="5"/></svg>
              <math><mi>&#x3C0;</mi></math>
            </container>
          XML
        end

        it "captures each raw element independently" do
          doc = MultiRawContainer.from_xml(multi_xml)
          expect(doc.name).to eq("mixed content")
          expect(doc.svg_data).to include("<svg")
          expect(doc.svg_data).to include("<circle")
          expect(doc.math_data).to include("<math>")
          expect(doc.math_data).to include("<mi>")
        end
      end

      describe "collection raw_element" do
        let(:collection_xml) do
          <<~XML
            <container>
              <name>multi</name>
              <fragment id="1">first</fragment>
              <fragment id="2">second</fragment>
              <fragment id="3"><nested>third</nested></fragment>
            </container>
          XML
        end

        it "captures each occurrence as a collection item" do
          doc = CollectionRawContainer.from_xml(collection_xml)
          expect(doc.name).to eq("multi")
          expect(doc.fragments.length).to eq(3)
          expect(doc.fragments[0]).to include("<fragment")
          expect(doc.fragments[0]).to include("first")
          expect(doc.fragments[1]).to include("second")
          expect(doc.fragments[2]).to include("<nested>third</nested>")
        end
      end

      describe "missing raw element" do
        it "returns nil when raw element is absent" do
          doc = SvgContainer.from_xml("<container><other>text</other></container>")
          expect(doc.svg_data).to be_nil
        end
      end

      describe "empty raw element" do
        it "captures self-closing empty element" do
          doc = EmptyRawContainer.from_xml("<container><name>test</name><foreign/></container>")
          expect(doc.embedded).to include("<foreign")
          expect(doc.embedded).to include("/")
        end
      end

      describe "XML special characters" do
        it "preserves entities in raw element content" do
          xml = "<container><foreign>a &amp; b &lt; c</foreign></container>"
          doc = MixedContainer.from_xml("<container><name>test</name>#{xml.match(/<container>(.*)<\/container>/m)[1]}</container>")
          expect(doc.embedded).to include("<foreign")
        end
      end

      describe "namespace matching" do
        it "captures element with xmlns declaration on itself" do
          doc = SvgContainer.from_xml(
            '<container><svg xmlns="http://www.w3.org/2000/svg"><rect/></svg></container>'
          )
          expect(doc.svg_data).to include("<svg")
          expect(doc.svg_data).to include('xmlns="http://www.w3.org/2000/svg"')
        end

        it "captures element with no namespace" do
          doc = SvgContainer.from_xml(
            "<container><svg><rect/></svg></container>"
          )
          expect(doc.svg_data).to include("<svg")
          expect(doc.svg_data).to include("<rect")
        end

        it "does not capture explicitly prefixed element" do
          doc = SvgContainer.from_xml(
            '<container xmlns:s="http://www.w3.org/2000/svg"><s:svg><s:rect/></s:svg></container>'
          )
          expect(doc.svg_data).to be_nil
        end
      end
    end

    describe "serialization" do
      describe "round-trip with SVG" do
        let(:svg_xml) do
          <<~XML
            <container>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
                <rect x="0" y="0" width="100" height="100" fill="red"/>
              </svg>
            </container>
          XML
        end

        it "preserves SVG data through parse -> serialize -> parse" do
          doc = SvgContainer.from_xml(svg_xml)
          output = doc.to_xml
          doc2 = SvgContainer.from_xml(output)
          expect(doc2.svg_data).to include("<svg")
          expect(doc2.svg_data).to include("</svg>")
          expect(doc2.svg_data).to include("viewBox")
          expect(doc2.svg_data).to include("<rect")
          expect(doc2.svg_data).to include("xmlns=\"http://www.w3.org/2000/svg\"")
        end
      end

      describe "round-trip with mixed content" do
        let(:mixed_xml) do
          '<container><name>test</name><foreign attr="value"><child>content</child></foreign></container>'
        end

        it "preserves both normal and raw elements" do
          doc = MixedContainer.from_xml(mixed_xml)
          output = doc.to_xml
          doc2 = MixedContainer.from_xml(output)
          expect(doc2.name).to eq("test")
          expect(doc2.embedded).to include("<foreign")
          expect(doc2.embedded).to include("attr=\"value\"")
          expect(doc2.embedded).to include("<child>content</child>")
        end
      end

      describe "round-trip with nested raw XML" do
        let(:nested_xml) do
          '<container><name>test</name><embedded><level1><level2 attr="deep">text</level2></level1></embedded></container>'
        end

        it "preserves full nesting depth" do
          doc = NestedRawContainer.from_xml(nested_xml)
          output = doc.to_xml
          doc2 = NestedRawContainer.from_xml(output)
          expect(doc2.embedded).to include("<level1>")
          expect(doc2.embedded).to include("<level2 attr=\"deep\">text</level2>")
          expect(doc2.embedded).to include("</level1>")
        end
      end

      describe "building from model instance" do
        it "serializes a programmatically created model" do
          model = SvgContainer.new(svg_data: '<svg xmlns="http://www.w3.org/2000/svg"><circle r="5"/></svg>')
          xml = model.to_xml
          expect(xml).to include("<svg")
          expect(xml).to include("<circle")
          expect(xml).to include("</svg>")
        end

        it "round-trips a programmatically created model" do
          original_svg = '<svg xmlns="http://www.w3.org/2000/svg"><circle r="5"/></svg>'
          model = SvgContainer.new(svg_data: original_svg)
          xml = model.to_xml
          doc = SvgContainer.from_xml(xml)
          expect(doc.svg_data).to include("<svg")
          expect(doc.svg_data).to include("<circle")
          expect(doc.svg_data).to include("</svg>")
        end

        it "does not double-escape raw element content" do
          model = SvgContainer.new(svg_data: "<svg><rect/></svg>")
          xml = model.to_xml
          expect(xml).not_to include("&lt;svg")
          expect(xml).not_to include("&gt;")
        end
      end

      describe "round-trip with collection" do
        let(:collection_xml) do
          <<~XML
            <container>
              <name>multi</name>
              <fragment id="1">first</fragment>
              <fragment id="2">second</fragment>
            </container>
          XML
        end

        it "preserves all collection items" do
          doc = CollectionRawContainer.from_xml(collection_xml)
          output = doc.to_xml
          doc2 = CollectionRawContainer.from_xml(output)
          expect(doc2.fragments.length).to eq(2)
          expect(doc2.fragments[0]).to include("first")
          expect(doc2.fragments[1]).to include("second")
        end
      end

      describe "nil and empty values" do
        it "omits raw element when value is nil" do
          model = SvgContainer.new(svg_data: nil)
          xml = model.to_xml
          expect(xml).not_to include("<svg")
        end

        it "omits raw element when value is empty string" do
          model = SvgContainer.new(svg_data: "")
          xml = model.to_xml
          expect(xml).not_to include("<svg")
        end
      end

      describe "XML special characters round-trip" do
        it "preserves angle brackets in raw element content without double-escaping" do
          doc = MixedContainer.from_xml(
            '<container><name>test</name><foreign><child a="1">x &amp; y</child></foreign></container>',
          )
          output = doc.to_xml
          expect(output).to include("<child")
          expect(output).not_to include("&lt;child")
          doc2 = MixedContainer.from_xml(output)
          expect(doc2.embedded).to include("<child")
          expect(doc2.embedded).to include("x &amp; y")
        end
      end
    end

    describe "default behavior (raw_element: false)" do
      it "does not capture raw XML for normal map_element" do
        doc = NormalContainer.from_xml("<container><data>text</data></container>")
        expect(doc.data).to eq("text")
        expect(doc.data).not_to include("<data>")
      end

      it "serializes text content normally" do
        model = NormalContainer.new(data: "hello")
        xml = model.to_xml
        expect(xml).to include("<data>hello</data>")
        expect(xml).not_to include("&lt;")
      end
    end

    describe "MappingRule attributes" do
      it "defaults raw_element to false" do
        rule = MixedContainer.mappings_for(:xml).elements.find do |r|
          r.to == :name
        end
        expect(rule.raw_element).to be(false)
      end

      it "sets raw_element to true when specified" do
        rule = MixedContainer.mappings_for(:xml).elements.find do |r|
          r.to == :embedded
        end
        expect(rule.raw_element).to be(true)
      end

      it "propagates raw_element through deep_dup" do
        rule = MixedContainer.mappings_for(:xml).elements.find do |r|
          r.to == :embedded
        end
        dup = rule.deep_dup
        expect(dup.raw_element).to be(true)
      end
    end
  end
end
