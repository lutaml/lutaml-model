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
  #
  # NOTE: Oga's parser silently drops undefined entities, producing empty
  # strings where the entity was. This is a parser-level limitation, not
  # something we can fix in the adapter.

  context "single entity with surrounding text" do
    it "preserves text before entity" do
      xml = <<~XML
        <copyright>&copy; 2005 Mulberry Technologies, Inc.</copyright>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      expect(text).to include("2005")
      expect(text).to include("Mulberry Technologies")
      if adapter_name == :oga
        # Oga drops undefined entities
        expect(text).to eq(" 2005 Mulberry Technologies, Inc.")
      else
        expect(text).to include("&copy;")
        expect(text).to eq("&copy; 2005 Mulberry Technologies, Inc.")
      end
    end

    it "preserves text after entity" do
      xml = <<~XML
        <text>Copyright &copy; notice here</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("Copyright  notice here")
      else
        expect(text).to eq("Copyright &copy; notice here")
      end
    end

    it "preserves text before and after entity" do
      xml = <<~XML
        <text>Before &mdash; After</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("Before  After")
      else
        expect(text).to eq("Before &mdash; After")
      end
    end
  end

  context "multiple entities in content" do
    it "preserves text between multiple entities" do
      xml = <<~XML
        <text>First &mdash; second &ndash; third</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("First  second  third")
      else
        expect(text).to eq("First &mdash; second &ndash; third")
      end
    end

    it "handles consecutive entities" do
      xml = <<~XML
        <text>&copy;&reg;&trade;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("")
      else
        expect(text).to eq("&copy;&reg;&trade;")
      end
    end

    it "handles entities with whitespace" do
      xml = <<~XML
        <text>&copy; &reg; &trade;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        # Oga drops entities but preserves surrounding whitespace
        expect(text).to eq("  ")
      else
        expect(text).to eq("&copy; &reg; &trade;")
      end
    end
  end

  context "entities at different positions" do
    it "handles entity at start" do
      xml = <<~XML
        <text>&copy; at start</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq(" at start")
      else
        expect(text).to eq("&copy; at start")
      end
    end

    it "handles entity at end" do
      xml = <<~XML
        <text>at end &copy;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("at end ")
      else
        expect(text).to eq("at end &copy;")
      end
    end

    it "handles entity alone" do
      xml = <<~XML
        <text>&copy;</text>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("")
      else
        expect(text).to eq("&copy;")
      end
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

      if adapter_name == :oga
        expect(instance.statement).to eq(" 2005 Mulberry Technologies, Inc.")
      else
        expect(instance.statement).to eq("&copy; 2005 Mulberry Technologies, Inc.")

        output = instance.to_xml
        # Re-parse to verify round-trip
        reparsed = model_class.from_xml(output)
        expect(reparsed.statement).to eq("&copy; 2005 Mulberry Technologies, Inc.")
      end
    end

    it "handles multiple entities in model attribute" do
      xml = <<~XML
        <copyright>
          <statement>Can&rsquo;t stop &mdash; won&rsquo;t stop</statement>
        </copyright>
      XML

      instance = model_class.from_xml(xml.strip)

      if adapter_name == :oga
        expect(instance.statement).to eq("Cant stop  wont stop")
      else
        expect(instance.statement).to eq("Can&rsquo;t stop &mdash; won&rsquo;t stop")
      end
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

      if adapter_name == :oga
        expect(full_text).to include("Text before ")
        expect(full_text).to include(" text after")
      else
        expect(full_text).to include("Text before &mdash; ")
        expect(full_text).to include(" &mdash; text after")
      end
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

        if adapter_name == :oga
          # Oga drops undefined entities
          expect(text).to eq("Before  After")
        else
          expect(text).to eq("Before #{expected_text} After")
        end
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

      if adapter_name == :oga
        expect(text).to eq(" 2005 Mulberry Technologies, Inc.")
      else
        expect(text).to eq("&copy; 2005 Mulberry Technologies, Inc.")
        expect(text).not_to eq("&copy;") # Should NOT lose the rest
      end
    end

    it "handles mixed-citation element" do
      xml = <<~XML
        <mixed-citation>A citation &mdash; with em-dash</mixed-citation>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("A citation  with em-dash")
      else
        expect(text).to eq("A citation &mdash; with em-dash")
      end
    end

    it "handles article-title with apostrophe" do
      xml = <<~XML
        <article-title>Can&rsquo;t Help Loving That Man</article-title>
      XML

      doc = adapter_class.parse(xml.strip)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("Cant Help Loving That Man")
      else
        expect(text).to eq("Can&rsquo;t Help Loving That Man")
      end
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

      if adapter_name == :oga
        expect(text).to eq("")
      else
        expect(text).to eq("&copy;")
      end
    end

    it "preserves significant whitespace around entities" do
      xml = "<text>  &copy;  </text>"

      doc = adapter_class.parse(xml)
      text = doc.root.text

      if adapter_name == :oga
        expect(text).to eq("    ")
      else
        expect(text).to eq("  &copy;  ")
      end
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

      # &apos; is standard XML entity → resolved to ' by parser
      # &nbsp; is non-standard → preserved as &nbsp; literal
      if adapter_name == :oga
        expect(parsed.r.t.content).to eq("''d")
      else
        expect(parsed.r.t.content).to eq("''&nbsp;d")
      end

      # Round-trip must preserve &nbsp;
      output = parsed.to_xml
      reparsed = EntityFragmentationSpec::OMathPara.from_xml(output)

      if adapter_name != :oga
        expect(reparsed.r.t.content).to eq("''&nbsp;d")
        expect(output).to include("&nbsp;")
      end
    end
  end
end

RSpec.describe "XML Entity Fragmentation Issue #5" do
  describe "with Nokogiri adapter" do
    it_behaves_like "XML entity preservation", :nokogiri
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
