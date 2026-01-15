require "spec_helper"

module MapAllSpec
  class Document < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      element "document"
      map_all to: :content
    end

    json do
      map_all to: :content
    end

    yaml do
      map_all to: :content
    end

    toml do
      map_all to: :content
    end
  end

  class InvalidDocument < Lutaml::Model::Serializable
    attribute :content, :string
    attribute :title, :string

    json do
      map_all to: :content
    end

    yaml do
      map_element "title", to: :title
    end
  end

  RSpec.describe "MapAll" do
    describe "XML serialization" do
      let(:xml_content) do
        <<~XML
          <document>
            Content with <b>tags</b> and <i>formatting</i>.
            <metadata>
              <author>John Doe</author>
              <date>2024-01-15</date>
            </metadata>
          </document>
        XML
      end

      let(:sub_xml_content) do
        # Match the exact whitespace as captured: leading newline + 2 spaces
        "\n  Content with <b>tags</b> and <i>formatting</i>.\n  <metadata>\n    <author>John Doe</author>\n    <date>2024-01-15</date>\n  </metadata>\n"
      end

      it "captures all XML content" do
        doc = Document.from_xml(xml_content)
        # Wrap both in a temporary root element for comparison since the content
        # starts with text (mixed content) and cannot be parsed as standalone XML
        wrapped_actual = "<root>#{doc.content}</root>"
        wrapped_expected = "<root>#{sub_xml_content}</root>"
        expect(wrapped_actual).to be_xml_equivalent_to(wrapped_expected)
      end

      it "preserves XML content through round trip" do
        doc = Document.from_xml(xml_content)
        regenerated = doc.to_xml
        expect(regenerated).to be_xml_equivalent_to(xml_content)
      end
    end

    describe "JSON serialization" do
      let(:json_content) do
        {
          "sections" => [
            { "title" => "Introduction", "text" => "Chapter 1" },
            { "title" => "Conclusion", "text" => "Final chapter" },
          ],
          "metadata" => {
            "author" => "John Doe",
            "date" => "2024-01-15",
          },
        }.to_json
      end

      it "captures all JSON content" do
        doc = Document.from_json(json_content)
        parsed = JSON.parse(doc.content)
        expect(parsed["sections"].first["title"]).to eq("Introduction")
        expect(parsed["metadata"]["author"]).to eq("John Doe")
      end

      it "preserves JSON content through round trip" do
        doc = Document.from_json(json_content)
        regenerated = doc.to_json
        expect(JSON.parse(regenerated)).to eq(JSON.parse(json_content))
      end
    end

    describe "YAML serialization" do
      let(:yaml_content) do
        <<~YAML
          sections:
            - title: Introduction
              text: Chapter 1
            - title: Conclusion
              text: Final chapter
          metadata:
            author: John Doe
            date: 2024-01-15
        YAML
      end

      it "captures all YAML content" do
        doc = Document.from_yaml(yaml_content)
        parsed = YAML.safe_load(doc.content, permitted_classes: [Date])
        expect(parsed["sections"].first["title"]).to eq("Introduction")
        expect(parsed["metadata"]["author"]).to eq("John Doe")
      end

      it "preserves YAML content through round trip" do
        doc = Document.from_yaml(yaml_content)
        regenerated = doc.to_yaml
        expect(YAML.safe_load(regenerated,
                              permitted_classes: [Date])).to eq(YAML.safe_load(yaml_content,
                                                                               permitted_classes: [Date]))
      end
    end

    describe "TOML serialization" do
      let(:toml_content) do
        <<~TOML
          title = "Document Title"

          [metadata]
          author = "John Doe"
          date = "2024-01-15"

          [[sections]]
          title = "Introduction"
          text = "Chapter 1"

          [[sections]]
          title = "Conclusion"
          text = "Final chapter"
        TOML
      end

      it "captures all TOML content" do
        doc = Document.from_toml(toml_content)
        parsed = TomlRB.parse(doc.content)
        expect(parsed["sections"].first["title"]).to eq("Introduction")
        expect(parsed["metadata"]["author"]).to eq("John Doe")
      end

      it "preserves TOML content through round trip" do
        doc = Document.from_toml(toml_content)
        regenerated = doc.to_toml
        expect(TomlRB.parse(regenerated)).to eq(TomlRB.parse(toml_content))
      end
    end

    describe "invalid mapping combinations" do
      it "raises error when combining map_all with other mappings" do
        expect do
          InvalidDocument.json do
            map_element "title", to: :title
          end
        end.to raise_error(
          StandardError,
          "map_all is not allowed with other mappings",
        )
      end

      it "raises error when combining other mappings are used with map_all" do
        expect do
          InvalidDocument.yaml do
            map_element "title", to: :title
            map_all to: :content
          end
        end.to raise_error(
          StandardError,
          "map_all is not allowed with other mappings",
        )
      end
    end
  end
end
