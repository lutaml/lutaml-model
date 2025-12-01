# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML Namespace Prefix-Independent Parsing" do
  # Test with all available XML adapters
  %i[nokogiri ox oga].each do |adapter_type|
    context "with #{adapter_type} adapter" do
      before do
        Lutaml::Model::Config.xml_adapter_type = adapter_type
      end

      # Define namespace classes for testing
      let(:ceramic_namespace) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/ceramic"
          prefix_default "cer"
          element_form_default :qualified
        end
      end

      let(:glaze_namespace) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/glaze"
          prefix_default "glz"
        end
      end

      let(:color_namespace) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/color"
          prefix_default "clr"
        end
      end

      describe "single namespace model" do
        let(:ceramic_class) do
          ns = ceramic_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :type, :string
            attribute :temperature, :integer

            xml do
              root "Ceramic"
              namespace ns
              map_element "Type", to: :type
              map_element "Temperature", to: :temperature
            end
          end
        end

        context "with default namespace (xmlns=...)" do
          let(:xml) do
            <<~XML
              <Ceramic xmlns="http://example.com/ceramic">
                <Type>Porcelain</Type>
                <Temperature>1300</Temperature>
              </Ceramic>
            XML
          end

          it "parses correctly" do
            result = ceramic_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.temperature).to eq(1300)
          end
        end

        context "with defined prefix (xmlns:cer=...)" do
          let(:xml) do
            <<~XML
              <cer:Ceramic xmlns:cer="http://example.com/ceramic">
                <cer:Type>Porcelain</cer:Type>
                <cer:Temperature>1300</cer:Temperature>
              </cer:Ceramic>
            XML
          end

          it "parses correctly" do
            result = ceramic_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.temperature).to eq(1300)
          end
        end

        context "with arbitrary prefix different from model definition" do
          let(:xml) do
            <<~XML
              <pottery:Ceramic xmlns:pottery="http://example.com/ceramic">
                <pottery:Type>Porcelain</pottery:Type>
                <pottery:Temperature>1300</pottery:Temperature>
              </pottery:Ceramic>
            XML
          end

          it "parses correctly" do
            result = ceramic_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.temperature).to eq(1300)
          end
        end

        context "with single letter prefix" do
          let(:xml) do
            <<~XML
              <c:Ceramic xmlns:c="http://example.com/ceramic">
                <c:Type>Porcelain</c:Type>
                <c:Temperature>1300</c:Temperature>
              </c:Ceramic>
            XML
          end

          it "parses correctly" do
            result = ceramic_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.temperature).to eq(1300)
          end
        end

        context "with numeric prefix" do
          let(:xml) do
            <<~XML
              <ns1:Ceramic xmlns:ns1="http://example.com/ceramic">
                <ns1:Type>Porcelain</ns1:Type>
                <ns1:Temperature>1300</ns1:Temperature>
              </ns1:Ceramic>
            XML
          end

          it "parses correctly" do
            result = ceramic_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.temperature).to eq(1300)
          end
        end
      end

      describe "nested model with different namespace" do
        let(:glaze_class) do
          ns = glaze_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :color, :string
            attribute :finish, :string

            xml do
              root "Glaze"
              namespace ns
              map_element "Color", to: :color
              map_element "Finish", to: :finish
            end
          end
        end

        let(:ceramic_with_glaze_class) do
          ns = ceramic_namespace
          glaze = glaze_class
          Class.new(Lutaml::Model::Serializable) do
            attribute :type, :string
            attribute :glaze, glaze

            xml do
              root "Ceramic"
              namespace ns
              map_element "Type", to: :type
              map_element "Glaze", to: :glaze
            end
          end
        end

        context "when parent with default namespace, child with prefix" do
          let(:xml) do
            <<~XML
              <Ceramic xmlns="http://example.com/ceramic" xmlns:glz="http://example.com/glaze">
                <Type>Porcelain</Type>
                <glz:Glaze>
                  <glz:Color>Clear</glz:Color>
                  <glz:Finish>Glossy</glz:Finish>
                </glz:Glaze>
              </Ceramic>
            XML
          end

          it "parses both parent and nested child correctly" do
            result = ceramic_with_glaze_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.glaze.color).to eq("Clear")
            expect(result.glaze.finish).to eq("Glossy")
          end
        end

        context "when parent with prefix, child with different prefix" do
          let(:xml) do
            <<~XML
              <cer:Ceramic xmlns:cer="http://example.com/ceramic" xmlns:g="http://example.com/glaze">
                <cer:Type>Porcelain</cer:Type>
                <g:Glaze>
                  <g:Color>Clear</g:Color>
                  <g:Finish>Glossy</g:Finish>
                </g:Glaze>
              </cer:Ceramic>
            XML
          end

          it "parses both with arbitrary prefixes" do
            result = ceramic_with_glaze_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.glaze.color).to eq("Clear")
            expect(result.glaze.finish).to eq("Glossy")
          end
        end

        context "when both parent and child with arbitrary prefixes" do
          let(:xml) do
            <<~XML
              <x:Ceramic xmlns:x="http://example.com/ceramic" xmlns:y="http://example.com/glaze">
                <x:Type>Porcelain</x:Type>
                <y:Glaze>
                  <y:Color>Clear</y:Color>
                  <y:Finish>Glossy</y:Finish>
                </y:Glaze>
              </x:Ceramic>
            XML
          end

          it "parses correctly" do
            result = ceramic_with_glaze_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.glaze.color).to eq("Clear")
            expect(result.glaze.finish).to eq("Glossy")
          end
        end
      end

      describe "type-level namespace" do
        let(:color_type) do
          ns = color_namespace
          Class.new(Lutaml::Model::Type::String) do
            xml_namespace ns
          end
        end

        let(:ceramic_with_color_type) do
          ns = ceramic_namespace
          color = color_type
          Class.new(Lutaml::Model::Serializable) do
            attribute :type, :string
            attribute :color, color

            xml do
              root "Ceramic"
              namespace ns
              map_element "Type", to: :type
              map_element "Color", to: :color
            end
          end
        end

        context "when type namespace with default, parent with prefix" do
          let(:xml) do
            <<~XML
              <cer:Ceramic xmlns:cer="http://example.com/ceramic" xmlns="http://example.com/color">
                <cer:Type>Porcelain</cer:Type>
                <Color>Navy Blue</Color>
              </cer:Ceramic>
            XML
          end

          it "parses type namespace correctly" do
            result = ceramic_with_color_type.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.color).to eq("Navy Blue")
          end
        end

        context "when type namespace with arbitrary prefix" do
          let(:xml) do
            <<~XML
              <Ceramic xmlns="http://example.com/ceramic" xmlns:c="http://example.com/color">
                <Type>Porcelain</Type>
                <c:Color>Navy Blue</c:Color>
              </Ceramic>
            XML
          end

          it "parses type namespace with arbitrary prefix" do
            result = ceramic_with_color_type.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.color).to eq("Navy Blue")
          end
        end
      end

      describe "collection with namespace" do
        let(:ceramic_collection_class) do
          ns = ceramic_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :items, :string, collection: true

            xml do
              root "Ceramics"
              namespace ns
              map_element "Item", to: :items
            end
          end
        end

        context "when collection elements with default namespace" do
          let(:xml) do
            <<~XML
              <Ceramics xmlns="http://example.com/ceramic">
                <Item>Porcelain</Item>
                <Item>Stoneware</Item>
                <Item>Earthenware</Item>
              </Ceramics>
            XML
          end

          it "parses all collection items" do
            result = ceramic_collection_class.from_xml(xml)
            expect(result.items).to eq(["Porcelain", "Stoneware", "Earthenware"])
          end
        end

        context "when collection elements with arbitrary prefix" do
          let(:xml) do
            <<~XML
              <art:Ceramics xmlns:art="http://example.com/ceramic">
                <art:Item>Porcelain</art:Item>
                <art:Item>Stoneware</art:Item>
                <art:Item>Earthenware</art:Item>
              </art:Ceramics>
            XML
          end

          it "parses all collection items with arbitrary prefix" do
            result = ceramic_collection_class.from_xml(xml)
            expect(result.items).to eq(["Porcelain", "Stoneware", "Earthenware"])
          end
        end
      end

      describe "namespace :inherit directive" do
        let(:parent_class) do
          ns = ceramic_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :name, :string
            attribute :description, :string

            xml do
              root "Parent"
              namespace ns
              map_element "Name", to: :name
              map_element "Description", to: :description, namespace: :inherit
            end
          end
        end

        context "when inherit with parent default namespace" do
          let(:xml) do
            <<~XML
              <Parent xmlns="http://example.com/ceramic">
                <Name>Test</Name>
                <Description>Inherits parent namespace</Description>
              </Parent>
            XML
          end

          it "parses inherited namespace element" do
            result = parent_class.from_xml(xml)
            expect(result.name).to eq("Test")
            expect(result.description).to eq("Inherits parent namespace")
          end
        end

        context "when inherit with parent prefixed namespace" do
          let(:xml) do
            <<~XML
              <cer:Parent xmlns:cer="http://example.com/ceramic">
                <cer:Name>Test</cer:Name>
                <cer:Description>Inherits parent namespace</cer:Description>
              </cer:Parent>
            XML
          end

          it "parses inherited namespace element with prefix" do
            result = parent_class.from_xml(xml)
            expect(result.name).to eq("Test")
            expect(result.description).to eq("Inherits parent namespace")
          end
        end

        context "when inherit with arbitrary parent prefix" do
          let(:xml) do
            <<~XML
              <x:Parent xmlns:x="http://example.com/ceramic">
                <x:Name>Test</x:Name>
                <x:Description>Inherits parent namespace</x:Description>
              </x:Parent>
            XML
          end

          it "parses with arbitrary prefix" do
            result = parent_class.from_xml(xml)
            expect(result.name).to eq("Test")
            expect(result.description).to eq("Inherits parent namespace")
          end
        end
      end

      describe "explicit namespace: nil (no namespace)" do
        let(:mixed_namespace_class) do
          ns = ceramic_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :type, :string
            attribute :note, :string

            xml do
              root "Ceramic"
              namespace ns
              map_element "Type", to: :type
              map_element "Note", to: :note, namespace: nil
            end
          end
        end

        context "when parent with namespace, child explicitly without" do
          let(:xml) do
            <<~XML
              <Ceramic xmlns="http://example.com/ceramic">
                <Type>Porcelain</Type>
                <Note xmlns="">This element has no namespace</Note>
              </Ceramic>
            XML
          end

          it "parses element without namespace" do
            result = mixed_namespace_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.note).to eq("This element has no namespace")
          end
        end

        context "when parent with prefix, child without namespace" do
          let(:xml) do
            <<~XML
              <cer:Ceramic xmlns:cer="http://example.com/ceramic">
                <cer:Type>Porcelain</cer:Type>
                <Note>This element has no namespace</Note>
              </cer:Ceramic>
            XML
          end

          it "parses element without namespace when parent is prefixed" do
            result = mixed_namespace_class.from_xml(xml)
            expect(result.type).to eq("Porcelain")
            expect(result.note).to eq("This element has no namespace")
          end
        end
      end

      describe "round-trip serialization with different prefix formats" do
        let(:ceramic_class) do
          ns = ceramic_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :type, :string

            xml do
              root "Ceramic"
              namespace ns
              map_element "Type", to: :type
            end
          end
        end

        it "parses default namespace and can serialize to prefix format" do
          xml_default = '<Ceramic xmlns="http://example.com/ceramic"><Type>Porcelain</Type></Ceramic>'

          parsed = ceramic_class.from_xml(xml_default)
          expect(parsed.type).to eq("Porcelain")

          serialized_prefixed = parsed.to_xml(prefix: true)
          expect(serialized_prefixed).to include("cer:Ceramic")
          expect(serialized_prefixed).to include('xmlns:cer="http://example.com/ceramic"')
        end

        it "parses prefixed namespace and can serialize to default format" do
          xml_prefixed = '<cer:Ceramic xmlns:cer="http://example.com/ceramic"><cer:Type>Porcelain</cer:Type></cer:Ceramic>'

          parsed = ceramic_class.from_xml(xml_prefixed)
          expect(parsed.type).to eq("Porcelain")

          serialized_default = parsed.to_xml
          expect(serialized_default).to include('<Ceramic xmlns="http://example.com/ceramic">')
        end

        it "parses arbitrary prefix and can round-trip" do
          xml_arbitrary = '<pottery:Ceramic xmlns:pottery="http://example.com/ceramic"><pottery:Type>Porcelain</pottery:Type></pottery:Ceramic>'

          parsed = ceramic_class.from_xml(xml_arbitrary)
          expect(parsed.type).to eq("Porcelain")

          # Should be able to serialize in both formats
          serialized_default = parsed.to_xml
          serialized_prefixed = parsed.to_xml(prefix: true)

          expect(ceramic_class.from_xml(serialized_default).type).to eq("Porcelain")
          expect(ceramic_class.from_xml(serialized_prefixed).type).to eq("Porcelain")
        end
      end
    end
  end
end
