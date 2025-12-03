# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

# Issue #5: HTML Entity Fragmentation in Mixed Content
# Related to: https://github.com/lutaml/lutaml-model/issues/XXX
# NISO-JATS Issue: Entities in mixed content cause text loss
RSpec.describe "XML Entity Fragmentation Issue #5" do
  context "single entity with surrounding text" do
    it "preserves text before entity" do
      xml = <<~XML
        <copyright>&copy; 2005 Mulberry Technologies, Inc.</copyright>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to include("©")
      expect(text).to include("2005")
      expect(text).to include("Mulberry Technologies")
      expect(text).to eq("© 2005 Mulberry Technologies, Inc.")
    end

    it "preserves text after entity" do
      xml = <<~XML
        <text>Copyright &copy; notice here</text>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Copyright © notice here")
    end

    it "preserves text before and after entity" do
      xml = <<~XML
        <text>Before &mdash; After</text>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Before — After")
    end
  end

  context "multiple entities in content" do
    it "preserves text between multiple entities" do
      xml = <<~XML
        <text>First &mdash; second &ndash; third</text>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("First — second – third")
    end

    it "handles consecutive entities" do
      xml = <<~XML
        <text>&copy;&reg;&trade;</text>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("©®™")
    end

    it "handles entities with whitespace" do
      xml = <<~XML
        <text>&copy; &reg; &trade;</text>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("© ® ™")
    end
  end

  context "entities at different positions" do
    it "handles entity at start" do
      xml = <<~XML
        <text>&copy; at start</text>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("© at start")
    end

    it "handles entity at end" do
      xml = <<~XML
        <text>at end &copy;</text>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("at end ©")
    end

    it "handles entity alone" do
      xml = <<~XML
        <text>&copy;</text>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("©")
    end
  end

  context "with model serialization round-trip" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :statement, :string

        xml do
          root "copyright"
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
      expect(instance.statement).to eq("© 2005 Mulberry Technologies, Inc.")

      output = instance.to_xml
      # Re-parse to verify
      reparsed = model_class.from_xml(output)
      expect(reparsed.statement).to eq("© 2005 Mulberry Technologies, Inc.")
    end

    it "handles multiple entities in model attribute" do
      xml = <<~XML
        <copyright>
          <statement>Can&rsquo;t stop &mdash; won&rsquo;t stop</statement>
        </copyright>
      XML

      instance = model_class.from_xml(xml.strip)
      expect(instance.statement).to eq("Can't stop — won't stop")
    end
  end

  context "mixed content with elements and entities" do
    let(:mixed_model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string, collection: true
        attribute :emphasis, :string

        xml do
          root "paragraph", mixed: true
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

      # Mixed content should preserve the full text including entities
      full_text = instance.content.join
      expect(full_text).to include("Text before — ")
      expect(full_text).to include(" — text after")
    end
  end

  context "common HTML entities" do
    entities = {
      "copy" => "©",
      "reg" => "®",
      "trade" => "™",
      "mdash" => "—",
      "ndash" => "–",
      "rsquo" => "'",
      "lsquo" => "'",
      "rdquo" => '"',
      "ldquo" => '"',
      "hellip" => "…",
      "nbsp" => "\u00A0",
      "amp" => "&",
      "lt" => "<",
      "gt" => ">",
      "quot" => '"',
    }
    
    entities.each do |entity_name, expected_char|
      it "correctly handles &#{entity_name}; entity" do
        xml = "<text>Before &#{entity_name}; After</text>"

        doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
        text = doc.root.text

        expect(text).to eq("Before #{expected_char} After")
      end
    end
  end

  context "numeric character references" do
    it "handles decimal numeric references" do
      xml = "<text>&#169; &#174; &#8212;</text>"

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
      text = doc.root.text

      expect(text).to eq("© ® —")
    end

    it "handles hexadecimal numeric references" do
      xml = "<text>&#xa9; &#xae; &#x2014;</text>"

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
      text = doc.root.text

      expect(text).to eq("© ® —")
    end

    it "handles numeric references with surrounding text" do
      xml = "<text>Copyright &#169; 2005</text>"

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
      text = doc.root.text

      expect(text).to eq("Copyright © 2005")
    end
  end

  context "real-world JATS examples" do
    it "handles copyright-statement element" do
      xml = <<~XML
        <copyright-statement>&copy; 2005 Mulberry Technologies, Inc.</copyright-statement>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("© 2005 Mulberry Technologies, Inc.")
      expect(text).not_to eq("©") # Should NOT lose the rest
    end

    it "handles mixed-citation element" do
      xml = <<~XML
        <mixed-citation>A citation &mdash; with em-dash</mixed-citation>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("A citation — with em-dash")
    end

    it "handles article-title with apostrophe" do
      xml = <<~XML
        <article-title>Can&rsquo;t Help Loving That Man</article-title>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml.strip)
      text = doc.root.text

      expect(text).to eq("Can't Help Loving That Man")
    end
  end

  context "edge cases" do
    it "handles empty elements" do
      xml = "<text></text>"

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
      text = doc.root.text

      expect(text).to eq("")
    end

    it "handles only whitespace" do
      xml = "<text>   </text>"

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
      text = doc.root.text

      expect(text).to eq("   ")
    end

    it "handles entity with no surrounding text" do
      xml = "<text>&copy;</text>"

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
      text = doc.root.text

      expect(text).to eq("©")
    end

    it "preserves significant whitespace around entities" do
      xml = "<text>  &copy;  </text>"

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml)
      text = doc.root.text

      expect(text).to eq("  ©  ")
    end
  end
end