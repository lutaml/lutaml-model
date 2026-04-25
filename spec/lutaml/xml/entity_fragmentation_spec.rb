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

  # Non-standard XML entities (like &copy;, &mdash;, &alpha;) are resolved
  # to their Unicode characters during parsing. This is correct XML behavior:
  # entity references are a serialization detail, not a data content feature.
  # Text content returns decoded characters; serialization preserves entity
  # references for round-trip fidelity.
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
      expect(text).to include("\u00A9")
      expect(text).to eq("\u00A9 2005 Mulberry Technologies, Inc.")
    end

    it "preserves text after entity" do
      xml = <<~XML
        <text>Copyright &copy; notice here</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Copyright \u00A9 notice here")
    end

    it "preserves text before and after entity" do
      xml = <<~XML
        <text>Before &mdash; After</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Before \u2014 After")
    end
  end

  context "multiple entities in content" do
    it "preserves text between multiple entities" do
      xml = <<~XML
        <text>First &mdash; second &ndash; third</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("First \u2014 second \u2013 third")
    end

    it "handles consecutive entities" do
      xml = <<~XML
        <text>&copy;&reg;&trade;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("\u00A9\u00AE\u2122")
    end

    it "handles entities with whitespace" do
      xml = <<~XML
        <text>&copy; &reg; &trade;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("\u00A9 \u00AE \u2122")
    end
  end

  context "entities at different positions" do
    it "handles entity at start" do
      xml = <<~XML
        <text>&copy; at start</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("\u00A9 at start")
    end

    it "handles entity at end" do
      xml = <<~XML
        <text>at end &copy;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("at end \u00A9")
    end

    it "handles entity alone" do
      xml = <<~XML
        <text>&copy;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("\u00A9")
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

      expect(instance.statement).to eq("\u00A9 2005 Mulberry Technologies, Inc.")

      output = instance.to_xml
      # Re-parse to verify round-trip
      reparsed = model_class.from_xml(output)
      expect(reparsed.statement).to eq("\u00A9 2005 Mulberry Technologies, Inc.")
    end

    it "handles multiple entities in model attribute" do
      xml = <<~XML
        <copyright>
          <statement>Can&rsquo;t stop &mdash; won&rsquo;t stop</statement>
        </copyright>
      XML

      instance = model_class.from_xml(xml.strip)

      expect(instance.statement).to eq("Can\u2019t stop \u2014 won\u2019t stop")
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

      expect(full_text).to include("Text before \u2014 ")
      expect(full_text).to include(" \u2014 text after")
    end
  end

  context "common non-standard XML entities" do
    # Non-standard entities are resolved to their Unicode characters
    non_standard_entities = {
      "copy" => "\u00A9",
      "reg" => "\u00AE",
      "trade" => "\u2122",
      "mdash" => "\u2014",
      "ndash" => "\u2013",
      "rsquo" => "\u2019",
      "lsquo" => "\u2018",
      "rdquo" => "\u201D",
      "ldquo" => "\u201C",
      "hellip" => "\u2026",
      "nbsp" => "\u00A0",
    }

    non_standard_entities.each do |entity_name, expected_char|
      it "correctly handles &#{entity_name}; entity (resolved to character)" do
        xml = "<text>Before &#{entity_name}; After</text>"

        doc = adapter_class.parse(xml)
        text = doc.root.text

        expect(text).to eq("Before #{expected_char} After")
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

      expect(text).to eq("\u00A9 2005 Mulberry Technologies, Inc.")
      expect(text).not_to eq("\u00A9") # Should NOT lose the rest
    end

    it "handles mixed-citation element" do
      xml = <<~XML
        <mixed-citation>A citation &mdash; with em-dash</mixed-citation>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("A citation \u2014 with em-dash")
    end

    it "handles article-title with apostrophe" do
      xml = <<~XML
        <article-title>Can&rsquo;t Help Loving That Man</article-title>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Can\u2019t Help Loving That Man")
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

      expect(text).to eq("\u00A9")
    end

    it "preserves significant whitespace around entities" do
      xml = "<text>  &copy;  </text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      expect(text).to eq("  \u00A9  ")
    end
  end

  context "namespaced content with mixed entities" do
    # Regression test: entities in namespaced elements must survive round-trip
    # &apos; (standard XML entity) resolves to ' during parse
    # &nbsp; (non-standard) is also resolved to its character during parse
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

      # Both standard and non-standard entities are resolved to characters
      expect(parsed.r.t.content).to eq("''\u00A0d")

      # Round-trip preserves content (decoded characters survive round-trip)
      output = parsed.to_xml
      reparsed = EntityFragmentationSpec::OMathPara.from_xml(output)

      expect(reparsed.r.t.content).to eq("''\u00A0d")
      # The non-breaking space character is preserved through round-trip
      expect(output).to include("\u00A0")
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
