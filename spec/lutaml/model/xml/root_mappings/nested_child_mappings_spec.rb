require "spec_helper"

module NestedChildMappingsSpec
  class ManifestFont < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :styles, :string, collection: true

    key_value do
      map "name", to: :name
      map "styles", to: :styles
    end
  end

  class ManifestResponseFontStyle < Lutaml::Model::Serializable
    attribute :full_name, :string
    attribute :type, :string
    attribute :paths, :string, collection: true

    key_value do
      map "full_name", to: :full_name
      map "type", to: :type
      map "paths", to: :paths
    end
  end

  class ManifestResponseFont < ManifestFont
    attribute :name, :string
    attribute :styles, ManifestResponseFontStyle, collection: true

    key_value do
      map "name", to: :name
      map "styles", to: :styles, child_mappings: {
        type: :key,
        full_name: :full_name,
        paths: :paths,
      }
    end
  end

  class ManifestResponse < Lutaml::Model::Collection
    instances :fonts, ManifestResponseFont

    key_value do
      map to: :fonts, root_mappings: {
        name: :key,
        styles: :value,
      }
    end
  end

  class ManifestResponseWrap < ManifestResponse
    # This class confirms the successful inhertiance of the `Collection` attribute.
  end
end

RSpec.describe "NestedChildMappingsSpec" do
  let(:yaml) do
    <<~YAML
      ---
      Yu Gothic:
        Bold:
          full_name: Yu Gothic Bold
          paths:
          - "/Applications/Microsoft Excel.app/Contents/Resources/DFonts/YuGothB.ttc"
          - "/Applications/Microsoft OneNote.app/Contents/Resources/DFonts/YuGothB.ttc"
          - "/Applications/Microsoft Outlook.app/Contents/Resources/DFonts/YuGothB.ttc"
          - "/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts/YuGothB.ttc"
          - "/Applications/Microsoft Word.app/Contents/Resources/DFonts/YuGothB.ttc"
        Regular:
          full_name: Yu Gothic Regular
          paths:
          - "/Applications/Microsoft Excel.app/Contents/Resources/DFonts/YuGothR.ttc"
          - "/Applications/Microsoft OneNote.app/Contents/Resources/DFonts/YuGothR.ttc"
          - "/Applications/Microsoft Outlook.app/Contents/Resources/DFonts/YuGothR.ttc"
          - "/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts/YuGothR.ttc"
          - "/Applications/Microsoft Word.app/Contents/Resources/DFonts/YuGothR.ttc"
      Noto Sans Condensed:
        Regular:
          full_name: Noto Sans Condensed
          paths:
          - "/Users/foo/.fontist/fonts/NotoSans-Condensed.ttf"
        Bold:
          full_name: Noto Sans Condensed Bold
          paths:
          - "/Users/foo/.fontist/fonts/NotoSans-CondensedBold.ttf"
        Bold Italic:
          full_name: Noto Sans Condensed Bold Italic
          paths:
          - "/Users/foo/.fontist/fonts/NotoSans-CondensedBoldItalic.ttf"
        Italic:
          full_name: Noto Sans Condensed Italic
          paths:
          - "/Users/foo/.fontist/fonts/NotoSans-CondensedItalic.ttf"
    YAML
  end

  let(:wrapped_yaml) do
    <<~YAML
      ---
      Yu Gothic:
        Bold:
          full_name: Yu Gothic Bold
          paths:
          - "/Applications/Microsoft Excel.app/Contents/Resources/DFonts/YuGothB.ttc"
          - "/Applications/Microsoft OneNote.app/Contents/Resources/DFonts/YuGothB.ttc"
          - "/Applications/Microsoft Outlook.app/Contents/Resources/DFonts/YuGothB.ttc"
          - "/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts/YuGothB.ttc"
          - "/Applications/Microsoft Word.app/Contents/Resources/DFonts/YuGothB.ttc"
        Regular:
          full_name: Yu Gothic Regular
          paths:
          - "/Applications/Microsoft Excel.app/Contents/Resources/DFonts/YuGothR.ttc"
          - "/Applications/Microsoft OneNote.app/Contents/Resources/DFonts/YuGothR.ttc"
          - "/Applications/Microsoft Outlook.app/Contents/Resources/DFonts/YuGothR.ttc"
          - "/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts/YuGothR.ttc"
          - "/Applications/Microsoft Word.app/Contents/Resources/DFonts/YuGothR.ttc"
      Noto Sans Condensed:
        Regular:
          full_name: Noto Sans Condensed
          paths:
          - "/Users/foo/.fontist/fonts/NotoSans-Condensed.ttf"
        Bold:
          full_name: Noto Sans Condensed Bold
          paths:
          - "/Users/foo/.fontist/fonts/NotoSans-CondensedBold.ttf"
        Bold Italic:
          full_name: Noto Sans Condensed Bold Italic
          paths:
          - "/Users/foo/.fontist/fonts/NotoSans-CondensedBoldItalic.ttf"
        Italic:
          full_name: Noto Sans Condensed Italic
          paths:
          - "/Users/foo/.fontist/fonts/NotoSans-CondensedItalic.ttf"
    YAML
  end

  let(:parsed_yaml) do
    NestedChildMappingsSpec::ManifestResponse.from_yaml(yaml)
  end

  let(:wrap_parsed_yaml) do
    NestedChildMappingsSpec::ManifestResponseWrap.from_yaml(wrapped_yaml)
  end

  let(:expected_fonts) do
    NestedChildMappingsSpec::ManifestResponse.new(
      [
        NestedChildMappingsSpec::ManifestResponseFont.new(
          name: "Yu Gothic",
          styles: [
            NestedChildMappingsSpec::ManifestResponseFontStyle.new(
              full_name: "Yu Gothic Bold",
              type: "Bold",
              paths: [
                "/Applications/Microsoft Excel.app/Contents/Resources/DFonts/YuGothB.ttc",
                "/Applications/Microsoft OneNote.app/Contents/Resources/DFonts/YuGothB.ttc",
                "/Applications/Microsoft Outlook.app/Contents/Resources/DFonts/YuGothB.ttc",
                "/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts/YuGothB.ttc",
                "/Applications/Microsoft Word.app/Contents/Resources/DFonts/YuGothB.ttc",
              ],
            ),
            NestedChildMappingsSpec::ManifestResponseFontStyle.new(
              full_name: "Yu Gothic Regular",
              type: "Regular",
              paths: [
                "/Applications/Microsoft Excel.app/Contents/Resources/DFonts/YuGothR.ttc",
                "/Applications/Microsoft OneNote.app/Contents/Resources/DFonts/YuGothR.ttc",
                "/Applications/Microsoft Outlook.app/Contents/Resources/DFonts/YuGothR.ttc",
                "/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts/YuGothR.ttc",
                "/Applications/Microsoft Word.app/Contents/Resources/DFonts/YuGothR.ttc",
              ],
            ),
          ],
        ),
        NestedChildMappingsSpec::ManifestResponseFont.new(
          name: "Noto Sans Condensed",
          styles: [
            NestedChildMappingsSpec::ManifestResponseFontStyle.new(
              full_name: "Noto Sans Condensed",
              type: "Regular",
              paths: ["/Users/foo/.fontist/fonts/NotoSans-Condensed.ttf"],
            ),
            NestedChildMappingsSpec::ManifestResponseFontStyle.new(
              full_name: "Noto Sans Condensed Bold",
              type: "Bold",
              paths: ["/Users/foo/.fontist/fonts/NotoSans-CondensedBold.ttf"],
            ),
            NestedChildMappingsSpec::ManifestResponseFontStyle.new(
              full_name: "Noto Sans Condensed Bold Italic",
              type: "Bold Italic",
              paths: ["/Users/foo/.fontist/fonts/NotoSans-CondensedBoldItalic.ttf"],
            ),
            NestedChildMappingsSpec::ManifestResponseFontStyle.new(
              full_name: "Noto Sans Condensed Italic",
              type: "Italic",
              paths: ["/Users/foo/.fontist/fonts/NotoSans-CondensedItalic.ttf"],
            ),
          ],
        ),
      ],
    )
  end

  it "parses nested child mappings correctly" do
    expect(parsed_yaml).to eq(expected_fonts)
  end

  it "rounds trip correctly" do
    expected_yaml = parsed_yaml.to_yaml
    expect(expected_yaml).to eq(yaml)
  end

  it "round trips nested child mappings correctly with Wrap class" do
    expected_yaml = wrap_parsed_yaml.to_yaml
    expect(expected_yaml).to eq(yaml)
  end
end
