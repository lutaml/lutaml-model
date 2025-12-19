# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML Encoding Handling" do
  shared_examples "encoding behavior" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string
        attribute :description, :string

        xml do
          element "Document"
          map_element "text", to: :text
          map_element "description", to: :description
        end
      end
    end

    context "UTF-8 encoding" do
      it "round-trips correctly" do
        original = model_class.new(
          text: "Hello UTF-8",
          description: "Unicode: © µ ∑ ∏"
        )

        xml = original.to_xml
        parsed = model_class.from_xml(xml)

        expect(parsed.text).to eq("Hello UTF-8")
        expect(parsed.description).to eq("Unicode: © µ ∑ ∏")
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
        expect(parsed.description.encoding).to eq(Encoding::UTF_8)
      end

      it "handles XML entities" do
        xml = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <Document>
            <text>Entity: &#xA9;</text>
            <description>Micro: &#xB5;</description>
          </Document>
        XML

        parsed = model_class.from_xml(xml)
        expect(parsed.text).to eq("Entity: ©")
        expect(parsed.description).to eq("Micro: µ")
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "Shift_JIS encoding" do
      it "converts to UTF-8 internally on parse" do
        shift_jis_xml = <<~XML.encode("Shift_JIS")
          <?xml version="1.0" encoding="Shift_JIS"?>
          <Document>
            <text>手書き英字</text>
            <description>日本語テキスト</description>
          </Document>
        XML

        parsed = model_class.from_xml(shift_jis_xml, encoding: "Shift_JIS")

        # Internal representation should be UTF-8
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
        expect(parsed.description.encoding).to eq(Encoding::UTF_8)

        # Content should be preserved
        expect(parsed.text).to eq("手書き英字")
        expect(parsed.description).to eq("日本語テキスト")
      end

      it "can output as Shift_JIS" do
        model = model_class.new(
          text: "手書き英字",
          description: "日本語テキスト"
        )

        shift_jis_xml = model.to_xml(encoding: "Shift_JIS")
        expect(shift_jis_xml.encoding).to eq(Encoding::Shift_JIS)
        expect(shift_jis_xml).to include('encoding="Shift_JIS"')

        # Should be valid Shift_JIS
        expect(shift_jis_xml.valid_encoding?).to be true
      end

      it "round-trips through Shift_JIS" do
        original = model_class.new(
          text: "手書き英字",
          description: "日本語"
        )

        # Serialize to Shift_JIS
        shift_jis_xml = original.to_xml(encoding: "Shift_JIS")

        # Parse back (should convert to UTF-8 internally)
        parsed = model_class.from_xml(shift_jis_xml, encoding: "Shift_JIS")

        expect(parsed.text).to eq(original.text)
        expect(parsed.description).to eq(original.description)
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "ISO-8859-1 encoding" do
      it "converts to UTF-8 internally on parse" do
        iso_xml = <<~XML.encode("ISO-8859-1")
          <?xml version="1.0" encoding="ISO-8859-1"?>
          <Document>
            <text>café résumé</text>
            <description>© µ</description>
          </Document>
        XML

        parsed = model_class.from_xml(iso_xml, encoding: "ISO-8859-1")

        # Internal representation should be UTF-8
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
        expect(parsed.description.encoding).to eq(Encoding::UTF_8)

        # Content should be preserved
        expect(parsed.text).to eq("café résumé")
        expect(parsed.description).to eq("© µ")
      end

      it "can output as ISO-8859-1" do
        model = model_class.new(
          text: "café résumé",
          description: "© µ"
        )

        iso_xml = model.to_xml(encoding: "ISO-8859-1")
        expect(iso_xml.encoding).to eq(Encoding::ISO_8859_1)
        expect(iso_xml).to include('encoding="ISO-8859-1"')

        # Should be valid ISO-8859-1
        expect(iso_xml.valid_encoding?).to be true
      end

      it "round-trips through ISO-8859-1" do
        original = model_class.new(
          text: "café",
          description: "© µ"
        )

        # Serialize to ISO-8859-1
        iso_xml = original.to_xml(encoding: "ISO-8859-1")

        # Parse back (should convert to UTF-8 internally)
        parsed = model_class.from_xml(iso_xml, encoding: "ISO-8859-1")

        expect(parsed.text).to eq(original.text)
        expect(parsed.description).to eq(original.description)
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "XML prolog encoding declaration" do
      it "respects encoding declaration in prolog" do
        xml_with_decl = <<~XML.encode("Shift_JIS")
          <?xml version="1.0" encoding="Shift_JIS"?>
          <Document>
            <text>手書き</text>
            <description>日本語</description>
          </Document>
        XML

        parsed = model_class.from_xml(xml_with_decl, encoding: "Shift_JIS")
        expect(parsed.text).to eq("手書き")
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
      end

      it "adds encoding declaration when serializing" do
        model = model_class.new(text: "test", description: "data")

        utf8_xml = model.to_xml(encoding: "UTF-8")
        expect(utf8_xml).to include('<?xml version="1.0" encoding="UTF-8"?>')

        shift_jis_xml = model.to_xml(encoding: "Shift_JIS")
        expect(shift_jis_xml).to include('encoding="Shift_JIS"')
      end
    end

    context "Unicode normalization" do
      it "preserves various Unicode characters" do
        original = model_class.new(
          text: "© µ ∑ ∏ ​",
          description: "Unicode test"
        )

        xml = original.to_xml
        parsed = model_class.from_xml(xml)

        expect(parsed.text).to eq("© µ ∑ ∏ ​")
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
      end

      it "handles zero-width characters" do
        original = model_class.new(
          text: "word​separator",  # Contains zero-width space
          description: "test"
        )

        xml = original.to_xml
        parsed = model_class.from_xml(xml)

        expect(parsed.text).to include("​")
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "mixed encoding scenarios" do
      it "handles UTF-8 input with entity references" do
        xml = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <Document>
            <text>Mix: © and &#xA9;</text>
            <description>Both forms</description>
          </Document>
        XML

        parsed = model_class.from_xml(xml)
        expect(parsed.text).to eq("Mix: © and ©")
        expect(parsed.text.encoding).to eq(Encoding::UTF_8)
      end

      it "converts from one encoding to another" do
        # Start with Shift_JIS
        shift_jis_xml = <<~XML.encode("Shift_JIS")
          <?xml version="1.0" encoding="Shift_JIS"?>
          <Document>
            <text>手書き</text>
            <description>test</description>
          </Document>
        XML

        parsed = model_class.from_xml(shift_jis_xml, encoding: "Shift_JIS")

        # Output as ISO-8859-1 (can't represent Japanese, but structure preserved)
        # This will fail for Japanese text, so use Latin text instead
        parsed.text = "café"
        iso_xml = parsed.to_xml(encoding: "ISO-8859-1")

        expect(iso_xml.encoding).to eq(Encoding::ISO_8859_1)
        expect(iso_xml).to include("café".encode("ISO-8859-1"))
      end
    end
  end

  if defined?(Lutaml::Model::Xml::NokogiriAdapter)
    describe "with Nokogiri adapter" do
      it_behaves_like "encoding behavior", Lutaml::Model::Xml::NokogiriAdapter
    end
  end

  if defined?(Lutaml::Model::Xml::OxAdapter)
    describe "with Ox adapter" do
      it_behaves_like "encoding behavior", Lutaml::Model::Xml::OxAdapter
    end
  end

  if defined?(Lutaml::Model::Xml::OgaAdapter)
    describe "with Oga adapter" do
      it_behaves_like "encoding behavior", Lutaml::Model::Xml::OgaAdapter
    end
  end
end