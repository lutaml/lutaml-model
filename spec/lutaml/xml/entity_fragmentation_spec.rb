# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/lutaml/model"
require_relative "../../support/test_namespaces"

module EntityFragmentationSpec
  # Classes for testing namespaced content with mixed entities
  class MathT < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      root "t"
      namespace OfficeMathNamespace
      map_content to: :content
    end
  end

  class MathR < Lutaml::Model::Serializable
    attribute :t, MathT

    xml do
      root "r"
      namespace OfficeMathNamespace
      map_element :t, to: :t
    end
  end

  class OMathPara < Lutaml::Model::Serializable
    attribute :r, MathR

    xml do
      root "oMathPara"
      namespace OfficeMathNamespace
      map_element :r, to: :r
    end
  end
end

# Issue #5: HTML Entity Fragmentation in Mixed Content
# Related to: https://github.com/lutaml/lutaml-model/issues/XXX
# NISO-JATS Issue: Entities in mixed content cause text loss
RSpec.shared_examples "XML entity preservation" do |adapter_name|
  before(:all) do
    Lutaml::Model::Config.xml_adapter_type = adapter_name
  end

  after(:all) do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  let(:adapter_class) { Lutaml::Model::Config.xml_adapter }

  # Non-standard XML entities (not defined in XML spec) should pass through
  # without being resolved to Unicode characters. We do NOT muck around
  # with entities — they survive round-trips as-is.
  #
  # Standard XML entities (&amp; &lt; &gt; &quot; &apos;) and numeric
  # character references (&#169; &#xa9;) are resolved by the XML parser
  # itself and remain as their character values.

  context "single entity with surrounding text" do
    it "preserves text before entity" do
      xml = <<~XML
        <copyright>&copy; 2005 Mulberry Technologies, Inc.</copyright>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to include("2005")
      expect(text).to include("Mulberry Technologies")
      expect(text).to include("&copy;")
      expect(text).to eq("&copy; 2005 Mulberry Technologies, Inc.")
    end

    it "preserves text after entity" do
      xml = <<~XML
        <text>Copyright &copy; notice here</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Copyright &copy; notice here")
    end

    it "preserves text before and after entity" do
      xml = <<~XML
        <text>Before &mdash; After</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Before &mdash; After")
    end
  end

  context "multiple entities in content" do
    it "preserves text between multiple entities" do
      xml = <<~XML
        <text>First &mdash; second &ndash; third</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("First &mdash; second &ndash; third")
    end

    it "handles consecutive entities" do
      xml = <<~XML
        <text>&copy;&reg;&trade;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("&copy;&reg;&trade;")
    end

    it "handles entities with whitespace" do
      xml = <<~XML
        <text>&copy; &reg; &trade;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("&copy; &reg; &trade;")
    end
  end

  context "entities at different positions" do
    it "handles entity at start" do
      xml = <<~XML
        <text>&copy; at start</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("&copy; at start")
    end

    it "handles entity at end" do
      xml = <<~XML
        <text>at end &copy;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("at end &copy;")
    end

    it "handles entity alone" do
      xml = <<~XML
        <text>&copy;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("&copy;")
    end
  end

  context "with model serialization round-trip" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :statement, :string

        xml do
          element "copyright"
          map_element "statement", to: :statement
        end
      end
    end

    it "preserves entity and surrounding text in round-trip" do
      xml = <<~XML
        <copyright>
          <statement>&copy; 2005 Mulberry Technologies, Inc.</statement>
        </copyright>
      XML

      instance = model_class.from_xml(xml.strip)

      expect(instance.statement).to eq("&copy; 2005 Mulberry Technologies, Inc.")

      output = instance.to_xml
      # Re-parse to verify round-trip
      reparsed = model_class.from_xml(output)
      expect(reparsed.statement).to eq("&copy; 2005 Mulberry Technologies, Inc.")
    end

    it "handles multiple entities in model attribute" do
      xml = <<~XML
        <copyright>
          <statement>Can&rsquo;t stop &mdash; won&rsquo;t stop</statement>
        </copyright>
      XML

      instance = model_class.from_xml(xml.strip)

      expect(instance.statement).to eq("Can&rsquo;t stop &mdash; won&rsquo;t stop")
    end
  end

  context "mixed content with elements and entities" do
    let(:mixed_model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string, collection: true
        attribute :emphasis, :string

        xml do
          element "paragraph"
          mixed_content

          map_content to: :content, mixed: true
          map_element "em", to: :emphasis
        end
      end
    end

    it "preserves text and entities around child elements" do
      xml = <<~XML
        <paragraph>Text before &mdash; <em>emphasized</em> &mdash; text after</paragraph>
      XML

      instance = mixed_model_class.from_xml(xml.strip)
      full_text = instance.content.join

      expect(full_text).to include("Text before &mdash; ")
      expect(full_text).to include(" &mdash; text after")
    end
  end

  context "common non-standard XML entities" do
    # Non-standard entities pass through as literal &name; text
    non_standard_entities = {
      "copy" => "&copy;",
      "reg" => "&reg;",
      "trade" => "&trade;",
      "mdash" => "&mdash;",
      "ndash" => "&ndash;",
      "rsquo" => "&rsquo;",
      "lsquo" => "&lsquo;",
      "rdquo" => "&rdquo;",
      "ldquo" => "&ldquo;",
      "hellip" => "&hellip;",
      "nbsp" => "&nbsp;",
    }

    non_standard_entities.each do |entity_name, expected_text|
      it "correctly handles &#{entity_name}; entity (passes through as-is)" do
        xml = "<text>Before &#{entity_name}; After</text>"

        doc = adapter_class.parse(xml)
        text = doc.root.text

        expect(text).to eq("Before #{expected_text} After")
      end
    end
  end

  context "standard XML entities" do
    # Standard XML entities are resolved by the XML parser itself
    standard_entities = {
      "amp" => "&",
      "lt" => "<",
      "gt" => ">",
      "quot" => '"',
    }

    standard_entities.each do |entity_name, expected_char|
      it "correctly handles &#{entity_name}; entity (resolved by XML parser)" do
        xml = "<text>Before &#{entity_name}; After</text>"

        doc = adapter_class.parse(xml)
        text = doc.root.text

        expect(text).to eq("Before #{expected_char} After")
      end
    end
  end

  context "numeric character references" do
    # Numeric references are resolved by the XML parser itself
    it "handles decimal numeric references" do
      xml = "<text>&#169; &#174; &#8212;</text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      expect(text).to eq("\u00A9 \u00AE \u2014")
    end

    it "handles hexadecimal numeric references" do
      xml = "<text>&#xa9; &#xae; &#x2014;</text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      expect(text).to eq("\u00A9 \u00AE \u2014")
    end

    it "handles numeric references with surrounding text" do
      xml = "<text>Copyright &#169; 2005</text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      expect(text).to eq("Copyright \u00A9 2005")
    end
  end

  context "real-world JATS examples" do
    it "handles copyright-statement element" do
      xml = <<~XML
        <copyright-statement>&copy; 2005 Mulberry Technologies, Inc.</copyright-statement>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("&copy; 2005 Mulberry Technologies, Inc.")
      expect(text).not_to eq("&copy;") # Should NOT lose the rest
    end

    it "handles mixed-citation element" do
      xml = <<~XML
        <mixed-citation>A citation &mdash; with em-dash</mixed-citation>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("A citation &mdash; with em-dash")
    end

    it "handles article-title with apostrophe" do
      xml = <<~XML
        <article-title>Can&rsquo;t Help Loving That Man</article-title>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Can&rsquo;t Help Loving That Man")
    end
  end

  context "edge cases" do
    it "handles empty elements" do
      xml = "<text></text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      expect(text).to eq("")
    end

    it "handles only whitespace" do
      xml = "<text>   </text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      expect(text).to eq("   ")
    end

    it "handles entity with no surrounding text" do
      xml = "<text>&copy;</text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      expect(text).to eq("&copy;")
    end

    it "preserves significant whitespace around entities" do
      xml = "<text>  &copy;  </text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      expect(text).to eq("  &copy;  ")
    end
  end

  context "namespaced content with mixed entities" do
    # Regression test: entities in namespaced elements must survive round-trip
    # &apos; (standard XML entity) resolves to ' during parse
    # &nbsp; (non-standard) must be preserved as &nbsp; in output
    it "preserves mixed entities in namespaced map_content" do
      skip "Ox adapter does not support OfficeMathNamespace" if adapter_name == :ox

      omml = <<~OMML
        <m:oMathPara xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
          <m:r>
            <m:t>&apos;&apos;&nbsp;d</m:t>
          </m:r>
        </m:oMathPara>
      OMML

      parsed = EntityFragmentationSpec::OMathPara.from_xml(omml)

      # &apos; is standard XML entity -> resolved to ' by parser
      # &nbsp; is non-standard -> preserved as &nbsp; literal
      expect(parsed.r.t.content).to eq("''&nbsp;d")

      # Round-trip must preserve &nbsp;
      output = parsed.to_xml
      reparsed = EntityFragmentationSpec::OMathPara.from_xml(output)

      expect(reparsed.r.t.content).to eq("''&nbsp;d")
      expect(output).to include("&nbsp;")
    end
  end
end

RSpec.describe "XML Entity Fragmentation Issue #5" do
  describe "with Nokogiri adapter" do
    it_behaves_like "XML entity preservation", :nokogiri

    # These tests exercise the adapter's to_xml path (build_xml → native
    # Nokogiri serialization), which is distinct from NokogiriElement#to_xml.
    context "adapter-level to_xml round-trip" do
      let(:adapter_class) { Lutaml::Xml::Adapter::NokogiriAdapter }

      it "preserves non-standard entity references" do
        doc = adapter_class.parse("<copyright>&copy; 2005 Mulberry</copyright>")
        output = doc.to_xml
        expect(output).to include("&copy;")
        expect(output).not_to include("&amp;copy;")
      end

      it "preserves double-escaped entity references" do
        doc = adapter_class.parse("<text>&amp;copy;</text>")
        output = doc.to_xml
        expect(output).to include("&amp;copy;")
        expect(output).not_to include("&amp;amp;")
      end

      it "preserves standard entities alongside non-standard" do
        doc = adapter_class.parse("<text>a &amp; b &copy; c</text>")
        output = doc.to_xml
        expect(output).to include("&amp;")
        expect(output).to include("&copy;")
        expect(output).not_to include("&amp;copy;")
      end

      it "preserves multiple non-standard entities" do
        doc = adapter_class.parse("<text>&copy; &mdash; &nbsp;</text>")
        output = doc.to_xml
        expect(output).to include("&copy;")
        expect(output).to include("&mdash;")
        expect(output).to include("&nbsp;")
      end
    end

    context "entity references in attribute values" do
      let(:adapter_class) { Lutaml::Xml::Adapter::NokogiriAdapter }

      it "preserves non-standard entities in attributes via element to_xml" do
        root = adapter_class.parse('<root attr="&copy; 2024"/>').root
        expect(root.to_xml).to include('attr="&copy; 2024"')
      end

      it "preserves non-standard entities in attributes via adapter to_xml" do
        doc = adapter_class.parse('<root attr="&copy; 2024"/>')
        output = doc.to_xml
        expect(output).to include('attr="&copy; 2024"')
      end

      it "re-escapes standard entities in attributes" do
        root = adapter_class.parse('<root attr="a &amp; b"/>').root
        expect(root.to_xml).to include('attr="a &amp; b"')
      end

      it "preserves double-escaped entities in attributes" do
        root = adapter_class.parse('<root attr="&amp;copy;"/>').root
        expect(root.to_xml).to include('attr="&amp;copy;"')
      end
    end

    # Model-level round-trip tests — these exercise the
    # build_xml_element / build_xml_node path which uses add_text_with_entities,
    # NOT the adapter-level NokogiriElement#build_xml path.
    context "model-level double-encoded entity round-trip" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            root "text"
            map_content to: :content
          end
        end
      end

      it "preserves &amp;lt; through model round-trip" do
        input = "<text>Escape &amp;lt; character</text>"
        instance = model_class.from_xml(input)
        output = instance.to_xml

        expect(output).to include("&amp;lt;")
        expect(output).not_to include("&lt; character")
      end

      it "preserves &amp;amp; through model round-trip" do
        input = "<text>if type gawk &gt; /dev/null 2&gt;&amp;1; then</text>"
        instance = model_class.from_xml(input)
        output = instance.to_xml

        expect(output).to include("&amp;1;")
        expect(output).not_to match(/[^a] &1/)
      end

      it "preserves double-encoded numeric character references" do
        input = '<text>&amp;#x5B9E;&amp;#x4F8B;.example</text>'
        instance = model_class.from_xml(input)
        output = instance.to_xml

        expect(output).to include("&amp;#x5B9E;")
        expect(output).to include("&amp;#x4F8B;")
      end

      it "preserves all five standard XML entities double-encoded" do
        input = "<text>&amp;lt; &amp;gt; &amp;apos; &amp;quot; &amp;amp;</text>"
        instance = model_class.from_xml(input)
        output = instance.to_xml

        expect(output).to include("&amp;lt;")
        expect(output).to include("&amp;gt;")
        expect(output).to include("&amp;apos;")
        expect(output).to include("&amp;quot;")
        expect(output).to include("&amp;amp;")
      end

      it "preserves non-standard entities in model round-trip" do
        input = "<text>Copyright &copy; 2024</text>"
        instance = model_class.from_xml(input)
        output = instance.to_xml

        expect(output).to include("&copy;")
        expect(output).not_to include("&amp;copy;")
      end

      it "preserves mixed standard and non-standard entities" do
        input = "<text>a &amp; b &copy; c &lt; d</text>"
        instance = model_class.from_xml(input)
        output = instance.to_xml

        expect(output).to include("&amp;")   # standard entity preserved
        expect(output).to include("&copy;")  # non-standard entity preserved
        expect(output).to include("&lt;")    # standard entity preserved
        expect(output).not_to include("&amp;copy;") # not double-escaped
      end
    end
  end

  describe "with Oga adapter" do
    if TestAdapterConfig.adapter_enabled?(:oga)
      it_behaves_like "XML entity preservation", :oga
    end
  end

  describe "with Ox adapter" do
    if TestAdapterConfig.adapter_enabled?(:ox)
      it_behaves_like "XML entity preservation", :ox
    end
  end

  describe "with REXML adapter" do
    if TestAdapterConfig.adapter_enabled?(:rexml)
      it_behaves_like "XML entity preservation", :rexml
    end
  end
end
