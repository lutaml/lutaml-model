require "spec_helper"
require "lutaml/model"

RSpec.describe "Namespace Preservation Issue #3" do
  context "unused namespace preservation" do
    it "preserves unused xmlns:xsi declaration from input" do
      xml_input = <<~XML
        <?xml version="1.0"?>
        <article xmlns="http://example.com/article" 
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <title>Test Article</title>
        </article>
      XML

      # Parse the XML
      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      
      # Verify input namespaces were captured
      expect(doc.input_namespaces).to include(:default)
      expect(doc.input_namespaces).to include("xsi")
      expect(doc.input_namespaces["xsi"][:uri]).to eq("http://www.w3.org/2001/XMLSchema-instance")
      
      # Re-serialize
      output = doc.to_xml
      
      # Verify xmlns:xsi is preserved in output
      expect(output).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      expect(output).to include('xmlns="http://example.com/article"')
    end

    it "preserves multiple unused namespace prefixes" do
      xml_input = <<~XML
        <root xmlns:ali="http://www.niso.org/schemas/ali/1.0/"
              xmlns:mml="http://www.w3.org/1998/Math/MathML"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <element>content</element>
        </root>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      # All three namespaces should be preserved
      expect(output).to include('xmlns:ali="http://www.niso.org/schemas/ali/1.0/"')
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
      expect(output).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    end
  end

  context "preventing unwanted namespace additions" do
    it "does not add namespaces not present in input" do
      xml_input = <<~XML
        <article xmlns:mml="http://www.w3.org/1998/Math/MathML">
          <title>Test</title>
        </article>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      # Should preserve mml namespace
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
      
      # Should NOT add namespaces that weren't in input
      # (assuming ali and oasis are not actually used in the content)
      expect(output).not_to include('xmlns:ali=')
      expect(output).not_to include('xmlns:oasis=')
    end
  end

  context "default namespace preservation" do
    it "preserves default namespace from input" do
      xml_input = <<~XML
        <article xmlns="http://jats.nlm.nih.gov/publishing/1.3">
          <title>Article Title</title>
          <abstract>Abstract content</abstract>
        </article>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      expect(output).to include('xmlns="http://jats.nlm.nih.gov/publishing/1.3"')
    end

    it "preserves both default and prefixed namespaces" do
      xml_input = <<~XML
        <article xmlns="http://example.com/default"
                 xmlns:special="http://example.com/special">
          <title>Title</title>
        </article>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      expect(output).to include('xmlns="http://example.com/default"')
      expect(output).to include('xmlns:special="http://example.com/special"')
    end
  end

  context "round-trip fidelity" do
    it "maintains exact namespace declarations through parse-serialize cycle" do
      xml_input = <<~XML
        <?xml version="1.0"?>
        <article xmlns="http://jats.nlm.nih.gov/publishing/1.3"
                 xmlns:mml="http://www.w3.org/1998/Math/MathML"
                 xmlns:xlink="http://www.w3.org/1999/xlink"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <front>
            <article-meta>
              <title-group>
                <article-title>Test Article</article-title>
              </title-group>
            </article-meta>
          </front>
        </article>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      # All four namespaces should be preserved
      expect(output).to include('xmlns="http://jats.nlm.nih.gov/publishing/1.3"')
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
      expect(output).to include('xmlns:xlink="http://www.w3.org/1999/xlink"')
      expect(output).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    end

    it "preserves namespace order (not guaranteed but nice to have)" do
      xml_input = <<~XML
        <root xmlns:a="http://a.com"
              xmlns:b="http://b.com"
              xmlns:c="http://c.com">
          <element/>
        </root>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      # All namespaces should be present (order not strictly required by XML spec)
      expect(output).to include('xmlns:a="http://a.com"')
      expect(output).to include('xmlns:b="http://b.com"')
      expect(output).to include('xmlns:c="http://c.com"')
    end
  end

  context "edge cases" do
    it "handles empty namespace prefix correctly" do
      xml_input = <<~XML
        <root xmlns="">
          <element>content</element>
        </root>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      # Empty namespace (explicit no namespace)
      expect(output).to include('xmlns=""')
    end

    it "handles documents without any namespace declarations" do
      xml_input = <<~XML
        <root>
          <child>content</child>
        </root>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      
      expect(doc.input_namespaces).to be_empty
      
      output = doc.to_xml
      # Should not have any xmlns declarations
      expect(output).not_to include('xmlns')
    end

    it "preservation works with complex nested structures" do
      xml_input = <<~XML
        <article xmlns="http://example.com"
                 xmlns:sec="http://example.com/section"
                 xmlns:unused="http://example.com/unused">
          <section>
            <title>Title</title>
            <para>
              <bold>Bold text</bold>
            </para>
          </section>
        </article>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      # All namespaces preserved, including unused
      expect(output).to include('xmlns="http://example.com"')
      expect(output).to include('xmlns:sec="http://example.com/section"')
      expect(output).to include('xmlns:unused="http://example.com/unused"')
    end
  end

  context "real-world JATS example" do
    it "preserves namespaces from actual JATS article" do
      xml_input = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE article PUBLIC "-//NLM//DTD JATS v1.3//EN" "JATS-journalpublishing1-3.dtd">
        <article xmlns:mml="http://www.w3.org/1998/Math/MathML"
                 xmlns:xlink="http://www.w3.org/1999/xlink"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                 xmlns:ali="http://www.niso.org/schemas/ali/1.0/">
          <front>
            <article-meta>
              <title-group>
                <article-title>Research Article</article-title>
              </title-group>
            </article-meta>
          </front>
          <body>
            <sec>
              <p>Article content here.</p>
            </sec>
          </body>
        </article>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      # Verify all JATS namespaces are preserved
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
      expect(output).to include('xmlns:xlink="http://www.w3.org/1999/xlink"')
      expect(output).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      expect(output).to include('xmlns:ali="http://www.niso.org/schemas/ali/1.0/"')
    end
  end

  context "namespace extraction API" do
    it "extract_input_namespaces returns correct structure" do
      xml = <<~XML
        <root xmlns="http://default.com"
              xmlns:pre="http://prefix.com">
          <child/>
        </root>
      XML

      parsed = Nokogiri::XML(xml)
      namespaces = Lutaml::Model::Xml::NokogiriAdapter.extract_input_namespaces(parsed.root)
      
      expect(namespaces).to be_a(Hash)
      expect(namespaces[:default]).to eq({ uri: "http://default.com", prefix: nil })
      expect(namespaces["pre"]).to eq({ uri: "http://prefix.com", prefix: "pre" })
    end

    it "extract_input_namespaces handles nil root element" do
      namespaces = Lutaml::Model::Xml::NokogiriAdapter.extract_input_namespaces(nil)
      expect(namespaces).to eq({})
    end
  end
end