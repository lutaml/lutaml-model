require "spec_helper"
require_relative "../../../lib/lutaml/model"

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
      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)

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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml

      # Should preserve mml namespace
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')

      # Should NOT add namespaces that weren't in input
      # (assuming ali and oasis are not actually used in the content)
      expect(output).not_to include("xmlns:ali=")
      expect(output).not_to include("xmlns:oasis=")
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)

      output = doc.to_xml
      # Should not have any xmlns declarations
      expect(output).not_to include("xmlns")
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
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

      doc = Lutaml::Xml::Adapter::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml

      # Verify all JATS namespaces are preserved
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
      expect(output).to include('xmlns:xlink="http://www.w3.org/1999/xlink"')
      expect(output).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      expect(output).to include('xmlns:ali="http://www.niso.org/schemas/ali/1.0/"')
    end
  end

  context "model-level round-trip preservation" do
    # These tests verify namespace preservation through the model layer
    # (Model.from_xml -> model.to_xml), not just adapter layer

    before do
      # Reset global state for test isolation
      Lutaml::Model::GlobalContext.clear_caches
      Lutaml::Model::TransformationRegistry.instance.clear
      Lutaml::Model::GlobalRegister.instance.reset
    end

    it "preserves unused namespace declarations at root through model round-trip" do
      # Define namespace class
      article_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/article"
        prefix_default "art"
      end

      # Define model class
      article_class = Class.new(Lutaml::Model::Serializable) do
        define_method(:initialize) do |attrs = {}|
          super(attrs)
        end

        attribute :title, :string

        xml do
          root "article"
          namespace article_ns
          map_element "title", to: :title
        end

        def self.name
          "Article"
        end
      end

      # Input XML has xmlns:xi for XInclude processing, but model doesn't use it
      xml_input = <<~XML
        <?xml version="1.0"?>
        <art:article xmlns:art="http://example.com/article"
                     xmlns:xi="http://www.w3.org/2001/XInclude">
          <art:title>Test Article</art:title>
        </art:article>
      XML

      # Parse to model
      article = article_class.from_xml(xml_input)
      expect(article.title).to eq("Test Article")

      # Serialize back to XML
      output = article.to_xml

      # Verify xmlns:xi is preserved (was declared at root in input)
      expect(output).to include('xmlns:xi="http://www.w3.org/2001/XInclude"')
      expect(output).to include('xmlns:art="http://example.com/article"')
    end

    it "preserves multiple unused namespace declarations at root" do
      # Define namespace class
      article_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/article"
        prefix_default "art"
      end

      # Define model class
      article_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string

        xml do
          root "article"
          namespace article_ns
          map_element "title", to: :title
        end

        def self.name
          "Article"
        end
      end

      xml_input = <<~XML
        <?xml version="1.0"?>
        <art:article xmlns:art="http://example.com/article"
                     xmlns:xi="http://www.w3.org/2001/XInclude"
                     xmlns:xlink="http://www.w3.org/1999/xlink"
                     xmlns:mml="http://www.w3.org/1998/Math/MathML">
          <art:title>Test Article</art:title>
        </art:article>
      XML

      article = article_class.from_xml(xml_input)
      output = article.to_xml

      # All unused namespaces should be preserved
      expect(output).to include('xmlns:xi="http://www.w3.org/2001/XInclude"')
      expect(output).to include('xmlns:xlink="http://www.w3.org/1999/xlink"')
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
    end

    it "does not hoist child-declared namespaces to root" do
      # Define namespace classes
      child_ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/child"
        prefix_default "child"
      end

      # Define child model class
      child_class = Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          root "child"
          namespace child_ns
          map_content to: :content
        end

        def self.name
          "Child"
        end
      end

      # Define parent model class
      parent_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :child, child_class

        xml do
          root "parent"
          map_element "title", to: :title
          map_element "child", to: :child
        end

        def self.name
          "Parent"
        end
      end

      xml_input = <<~XML
        <parent>
          <title>Parent Title</title>
          <child xmlns:child="http://example.com/child">Child Content</child>
        </parent>
      XML

      parent = parent_class.from_xml(xml_input)
      output = parent.to_xml

      # The child namespace should NOT be hoisted to root
      # (it was declared on child element in input)
      expect(output).not_to match(%r{<parent[^>]*xmlns:child=})
    end
  end
end
