require "spec_helper"
require "lutaml/model"

RSpec.shared_examples "DOCTYPE preservation" do |adapter_name|
  # Sample model for testing
  class DoctypeArticle < Lutaml::Model::Serializable
    attribute :title, :string
    attribute :content, :string

    xml do
      root "article"
      map_element "title", to: :title
      map_element "content", to: :content
    end
  end

  before(:all) do
    Lutaml::Model::Config.xml_adapter_type = adapter_name
  end

  context "PUBLIC DOCTYPE" do
    it "preserves PUBLIC DOCTYPE in round-trip" do
      xml = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE article PUBLIC "-//NLM//DTD JATS v1.3//EN" "JATS-journalpublishing1-3.dtd">
        <article>
          <title>Test Article</title>
          <content>Sample content</content>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      
      expect(doc.doctype).not_to be_nil
      expect(doc.doctype[:name]).to eq("article")
      expect(doc.doctype[:public_id]).to eq("-//NLM//DTD JATS v1.3//EN")
      expect(doc.doctype[:system_id]).to eq("JATS-journalpublishing1-3.dtd")

      output = doc.to_xml(declaration: true)
      
      expect(output).to include('<?xml version="1.0"')
      expect(output).to include('<!DOCTYPE article PUBLIC "-//NLM//DTD JATS v1.3//EN" "JATS-journalpublishing1-3.dtd">')
      expect(output).to include('<article>')
    end

    it "preserves PUBLIC DOCTYPE with model serialization" do
      xml = <<~XML
        <!DOCTYPE article PUBLIC "-//NLM//DTD JATS v1.3//EN" "JATS-journalpublishing1-3.dtd">
        <article>
          <title>Test</title>
          <content>Content</content>
        </article>
      XML

      article = DoctypeArticle.from_xml(xml)
      
      expect(article.title).to eq("Test")
      expect(article.content).to eq("Content")

      output = article.to_xml(declaration: true)
      
      # DOCTYPE should be preserved through model round-trip
      expect(output).to include('<!DOCTYPE article PUBLIC')
      expect(output).to include('-//NLM//DTD JATS v1.3//EN')
      expect(output).to include('JATS-journalpublishing1-3.dtd')
    end
  end

  context "SYSTEM DOCTYPE" do
    it "preserves SYSTEM DOCTYPE in round-trip" do
      xml = <<~XML
        <!DOCTYPE article SYSTEM "article.dtd">
        <article>
          <title>System DTD Test</title>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      
      expect(doc.doctype).not_to be_nil
      expect(doc.doctype[:name]).to eq("article")
      expect(doc.doctype[:public_id]).to be_nil
      expect(doc.doctype[:system_id]).to eq("article.dtd")

      output = doc.to_xml
      
      expect(output).to include('<!DOCTYPE article SYSTEM "article.dtd">')
    end

    it "preserves SYSTEM DOCTYPE with URL" do
      xml = <<~XML
        <!DOCTYPE article SYSTEM "http://example.com/dtd/article.dtd">
        <article>
          <title>URL DTD Test</title>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      output = doc.to_xml
      
      expect(output).to include('<!DOCTYPE article SYSTEM "http://example.com/dtd/article.dtd">')
    end
  end

  context "PUBLIC with SYSTEM DOCTYPE" do
    it "preserves both PUBLIC and SYSTEM identifiers" do
      xml = <<~XML
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
        <article>
          <title>XHTML Test</title>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      
      expect(doc.doctype[:name]).to eq("html")
      expect(doc.doctype[:public_id]).to eq("-//W3C//DTD XHTML 1.0 Strict//EN")
      expect(doc.doctype[:system_id]).to eq("http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd")

      output = doc.to_xml
      
      expect(output).to include('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">')
    end
  end

  context "omit_doctype option" do
    it "omits DOCTYPE when option is set" do
      xml = <<~XML
        <!DOCTYPE article PUBLIC "-//NLM//DTD JATS v1.3//EN" "JATS-journalpublishing1-3.dtd">
        <article>
          <title>Test</title>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      
      # DOCTYPE is stored
      expect(doc.doctype).not_to be_nil
      
      # But not serialized when omit_doctype is true
      output = doc.to_xml(omit_doctype: true)
      
      expect(output).not_to include('<!DOCTYPE')
      expect(output).to include('<article>')
    end
  end

  context "missing DOCTYPE" do
    it "handles XML without DOCTYPE gracefully" do
      xml = <<~XML
        <article>
          <title>No DOCTYPE</title>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      
      expect(doc.doctype).to be_nil
      
      output = doc.to_xml
      
      expect(output).not_to include('<!DOCTYPE')
      expect(output).to include('<article>')
    end

    it "does not add DOCTYPE when none exists" do
      article = DoctypeArticle.new(title: "Test", content: "Content")
      
      output = article.to_xml
      
      expect(output).not_to include('<!DOCTYPE')
    end
  end

  context "edge cases" do
    it "handles DOCTYPE with minimal information" do
      xml = <<~XML
        <!DOCTYPE article>
        <article>
          <title>Minimal DOCTYPE</title>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      
      expect(doc.doctype).not_to be_nil
      expect(doc.doctype[:name]).to eq("article")
    end

    it "preserves DOCTYPE with special characters in identifiers" do
      xml = <<~XML
        <!DOCTYPE article PUBLIC "-//Special//DTD Test v1.0//EN" "file:///path/to/test.dtd">
        <article>
          <title>Special Chars</title>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      output = doc.to_xml
      
      expect(output).to include('-//Special//DTD Test v1.0//EN')
      expect(output).to include('file:///path/to/test.dtd')
    end

    it "handles DOCTYPE declaration with XML declaration" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE article SYSTEM "article.dtd">
        <article>
          <title>Both Declarations</title>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      output = doc.to_xml(declaration: true, encoding: "UTF-8")
      
      expect(output).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(output).to include('<!DOCTYPE article SYSTEM "article.dtd">')
      
      # Verify order: declaration, then DOCTYPE, then root element
      declaration_pos = output.index('<?xml')
      doctype_pos = output.index('<!DOCTYPE')
      article_pos = output.index('<article>')
      
      expect(declaration_pos).to be < doctype_pos
      expect(doctype_pos).to be < article_pos
    end
  end

  context "real-world JATS example" do
    it "preserves complex JATS DOCTYPE declaration" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE article PUBLIC "-//NLM//DTD JATS (Z39.96) Journal Publishing DTD v1.3 20210610//EN" "JATS-journalpublishing1-3.dtd">
        <article xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:mml="http://www.w3.org/1998/Math/MathML">
          <title>JATS Article</title>
          <content>Complete JATS example</content>
        </article>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)
      
      expect(doc.doctype[:name]).to eq("article")
      expect(doc.doctype[:public_id]).to eq("-//NLM//DTD JATS (Z39.96) Journal Publishing DTD v1.3 20210610//EN")
      expect(doc.doctype[:system_id]).to eq("JATS-journalpublishing1-3.dtd")

      output = doc.to_xml(declaration: true, encoding: "UTF-8")
      
      expect(output).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(output).to include('<!DOCTYPE article PUBLIC "-//NLM//DTD JATS (Z39.96) Journal Publishing DTD v1.3 20210610//EN" "JATS-journalpublishing1-3.dtd">')
    end
  end

  context "doctype_declaration method" do
    it "generates correct PUBLIC DOCTYPE string" do
      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.new(
        nil,
        "UTF-8",
        doctype: {
          name: "article",
          public_id: "-//TEST//DTD Test v1.0//EN",
          system_id: "test.dtd"
        }
      )

      declaration = doc.doctype_declaration
      
      expect(declaration).to eq('<!DOCTYPE article PUBLIC "-//TEST//DTD Test v1.0//EN" "test.dtd">' + "\n")
    end

    it "generates correct SYSTEM DOCTYPE string" do
      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.new(
        nil,
        "UTF-8",
        doctype: {
          name: "article",
          public_id: nil,
          system_id: "article.dtd"
        }
      )

      declaration = doc.doctype_declaration
      
      expect(declaration).to eq('<!DOCTYPE article SYSTEM "article.dtd">' + "\n")
    end

    it "returns nil when no DOCTYPE" do
      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.new(nil, "UTF-8")
      
      expect(doc.doctype_declaration).to be_nil
    end
  end
end

RSpec.describe "DOCTYPE Preservation Issue #2" do
  describe "with Nokogiri adapter" do
    include_examples "DOCTYPE preservation", :nokogiri
  end

  describe "with Ox adapter" do
    include_examples "DOCTYPE preservation", :ox
  end

  describe "with Oga adapter" do
    include_examples "DOCTYPE preservation", :oga
  end
end