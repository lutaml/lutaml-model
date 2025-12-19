# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

RSpec.describe "XML Declaration Preservation" do
  describe "Issue #1: XML Declaration Preservation" do
    # Test model for declaration tests
    class XmlDeclModel < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :value, :integer

      xml do
        element "simple"
        map_element "name", to: :name
        map_element "value", to: :value
      end
    end

    describe "parsing XML with declaration" do
      it "detects XML declaration in input" do
        xml = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration).not_to be_nil
        expect(doc.xml_declaration[:had_declaration]).to be true
        expect(doc.xml_declaration[:version]).to eq("1.0")
        expect(doc.xml_declaration[:encoding]).to eq("UTF-8")
      end

      it "detects declaration with different version" do
        xml = <<~XML
          <?xml version="1.1" encoding="UTF-8"?>
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration[:version]).to eq("1.1")
      end

      it "detects declaration without encoding" do
        xml = <<~XML
          <?xml version="1.0"?>
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration[:had_declaration]).to be true
        expect(doc.xml_declaration[:version]).to eq("1.0")
        expect(doc.xml_declaration[:encoding]).to be_nil
      end

      it "detects declaration with different encoding" do
        xml = <<~XML
          <?xml version="1.0" encoding="ISO-8859-1"?>
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration[:encoding]).to eq("ISO-8859-1")
      end

      it "detects absence of XML declaration" do
        xml = <<~XML
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration).not_to be_nil
        expect(doc.xml_declaration[:had_declaration]).to be false
      end

      it "handles declaration with whitespace" do
        xml = "  \n  <?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<simple><name>Test</name><value>42</value></simple>"

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration[:had_declaration]).to be true
      end
    end

    describe "default behavior (preserve from input)" do
      context "when input had declaration" do
        it "preserves declaration in round-trip (Document)" do
          xml_in = <<~XML
            <?xml version="1.0" encoding="UTF-8"?>
            <simple>
              <name>Test</name>
              <value>42</value>
            </simple>
          XML

          doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_in)
          xml_out = doc.to_xml

          expect(xml_out).to start_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        end

        it "preserves declaration in round-trip (Model)" do
          xml_in = <<~XML
            <?xml version="1.0" encoding="UTF-8"?>
            <simple>
              <name>Test</name>
              <value>42</value>
            </simple>
          XML

          model = XmlDeclModel.from_xml(xml_in)
          xml_out = model.to_xml

          expect(xml_out).to start_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        end

        it "preserves version from input" do
          xml_in = <<~XML
            <?xml version="1.1" encoding="UTF-8"?>
            <simple>
              <name>Test</name>
              <value>42</value>
            </simple>
          XML

          model = XmlDeclModel.from_xml(xml_in)
          xml_out = model.to_xml

          expect(xml_out).to start_with("<?xml version=\"1.1\"")
        end

        it "preserves encoding from input" do
          xml_in = <<~XML
            <?xml version="1.0" encoding="ISO-8859-1"?>
            <simple>
              <name>Test</name>
              <value>42</value>
            </simple>
          XML

          doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_in)
          xml_out = doc.to_xml

          expect(xml_out).to include("encoding=\"ISO-8859-1\"")
        end

        it "preserves declaration without encoding attribute" do
          xml_in = <<~XML
            <?xml version="1.0"?>
            <simple>
              <name>Test</name>
              <value>42</value>
            </simple>
          XML

          doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_in)
          xml_out = doc.to_xml

          expect(xml_out).to start_with("<?xml version=\"1.0\"?>")
          expect(xml_out).not_to include("encoding=")
        end
      end

      context "when input had no declaration" do
        it "omits declaration in output (Document)" do
          xml_in = <<~XML
            <simple>
              <name>Test</name>
              <value>42</value>
            </simple>
          XML

          doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_in)
          xml_out = doc.to_xml

          expect(xml_out).not_to start_with("<?xml")
        end

        it "omits declaration in output (Model)" do
          xml_in = <<~XML
            <simple>
              <name>Test</name>
              <value>42</value>
            </simple>
          XML

          model = XmlDeclModel.from_xml(xml_in)
          xml_out = model.to_xml

          expect(xml_out).not_to start_with("<?xml")
        end
      end
    end

    describe "explicit declaration: true option" do
      it "forces declaration even if input had none" do
        xml_in = <<~XML
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: true)

        expect(xml_out).to start_with("<?xml version=\"1.0\"")
      end

      it "uses default version and encoding when forcing" do
        xml_in = "<simple><name>Test</name><value>42</value></simple>"

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: true, encoding: "UTF-8")

        expect(xml_out).to start_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      end

      it "overrides input declaration when forced" do
        xml_in = "<?xml version=\"1.1\"?><simple><name>Test</name><value>42</value></simple>"

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: true)

        # Should use default 1.0, not input 1.1
        expect(xml_out).to start_with("<?xml version=\"1.0\"")
      end
    end

    describe "explicit declaration: false option" do
      it "omits declaration even if input had one" do
        xml_in = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: false)

        expect(xml_out).not_to start_with("<?xml")
      end

      it "omits declaration when input had none" do
        xml_in = "<simple><name>Test</name><value>42</value></simple>"

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: false)

        expect(xml_out).not_to start_with("<?xml")
      end
    end

    describe "declaration: :preserve option" do
      it "preserves declaration if input had one" do
        xml_in = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: :preserve)

        expect(xml_out).to start_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      end

      it "omits declaration if input had none" do
        xml_in = "<simple><name>Test</name><value>42</value></simple>"

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: :preserve)

        expect(xml_out).not_to start_with("<?xml")
      end
    end

    describe "custom version via declaration option" do
      it "uses custom version string" do
        xml_in = "<simple><name>Test</name><value>42</value></simple>"

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: "1.1", encoding: "UTF-8")

        expect(xml_out).to start_with("<?xml version=\"1.1\" encoding=\"UTF-8\"?>")
      end
    end

    describe "encoding option interaction" do
      it "uses encoding option when declaration is forced" do
        xml_in = "<simple><name>Test</name><value>42</value></simple>"

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: true, encoding: "ISO-8859-1")

        expect(xml_out).to start_with("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>")
      end

      it "preserves input encoding when no encoding option provided" do
        xml_in = <<~XML
          <?xml version="1.0" encoding="Shift_JIS"?>
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_in)
        xml_out = doc.to_xml

        expect(xml_out).to include("encoding=\"Shift_JIS\"")
      end

      it "omits encoding attribute when none specified" do
        xml_in = "<?xml version=\"1.0\"?><simple><name>Test</name><value>42</value></simple>"

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_in)
        xml_out = doc.to_xml

        expect(xml_out).to start_with("<?xml version=\"1.0\"?>")
        expect(xml_out).not_to include("encoding=")
      end
    end

    describe "edge cases" do
      it "handles declaration with single quotes" do
        xml = "<?xml version='1.0' encoding='UTF-8'?><simple><name>Test</name><value>42</value></simple>"

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration[:had_declaration]).to be true
        expect(doc.xml_declaration[:version]).to eq("1.0")
        expect(doc.xml_declaration[:encoding]).to eq("UTF-8")
      end

      it "handles declaration with extra whitespace" do
        xml = "<?xml  version = \"1.0\"   encoding = \"UTF-8\" ?><simple><name>Test</name><value>42</value></simple>"

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration[:had_declaration]).to be true
      end

      it "handles standalone attribute in declaration" do
        xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><simple><name>Test</name><value>42</value></simple>"

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        expect(doc.xml_declaration[:had_declaration]).to be true
        expect(doc.xml_declaration[:version]).to eq("1.0")
        expect(doc.xml_declaration[:encoding]).to eq("UTF-8")
      end
    end

    describe "combined with DOCTYPE" do
      it "preserves both declaration and DOCTYPE in correct order" do
        xml_in = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE simple PUBLIC "-//Example//DTD Simple 1.0//EN" "http://example.com/simple.dtd">
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml

        # Declaration should come first, then DOCTYPE
        lines = xml_out.lines
        expect(lines[0]).to start_with("<?xml")
        expect(lines[1]).to start_with("<!DOCTYPE")
      end

      it "omits declaration but preserves DOCTYPE when declaration: false" do
        xml_in = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE simple SYSTEM "simple.dtd">
          <simple>
            <name>Test</name>
            <value>42</value>
          </simple>
        XML

        model = XmlDeclModel.from_xml(xml_in)
        xml_out = model.to_xml(declaration: false)

        expect(xml_out).not_to start_with("<?xml")
        expect(xml_out).to start_with("<!DOCTYPE")
      end
    end
  end
end