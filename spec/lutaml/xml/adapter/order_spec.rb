require "spec_helper"
require "lutaml/model"
require "lutaml/xml"
require "lutaml/xml/adapter/nokogiri_adapter"
require "lutaml/xml/adapter/ox_adapter"
require "lutaml/xml/adapter/oga_adapter"
require "lutaml/xml/adapter/rexml_adapter"

module XmlAdapterSharedFeaturesSpec
  class WordProcessingNamespace < Lutaml::Xml::Namespace
    uri "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    prefix_default "w"
    element_form_default :qualified
    attribute_form_default :qualified
  end

  class BooleanElement < Lutaml::Model::Serializable
    attribute :val, :string

    xml do
      element "b"
      namespace WordProcessingNamespace
      map_attribute :val, to: :val
    end
  end

  class ProcessingInstructionLookupElement < Lutaml::Model::Serializable
    attribute :foo, :string

    xml do
      root "root"
      map_element "foo", to: :foo
    end
  end
end

RSpec.describe "XML adapter order metadata" do
  shared_examples "consistent order metadata" do |adapter_class|
    let(:xml) do
      "<root>before<![CDATA[cdata text]]><?pi data?><child/>after</root>"
    end

    let(:document) { adapter_class.parse(xml) }

    let(:expected_order) do
      [
        ["Text", "text", :text, "before"],
        ["Text", "#cdata-section", :cdata, "cdata text"],
        ["ProcessingInstruction", "pi", :processing_instruction, "data"],
        ["Element", "child", :element, "child"],
        ["Text", "text", :text, "after"],
      ]
    end

    def order_data(order)
      order.map do |item|
        [item.type, item.name, item.node_type, item.text_content]
      end
    end

    it "uses the same order representation for root, document, and class order" do
      expect(order_data(document.root.order)).to eq(expected_order)
      expect(order_data(document.order)).to eq(expected_order)
      expect(order_data(adapter_class.order_of(document.root))).to eq(expected_order)
    end

    it "parses processing instructions as first-class XML nodes" do
      instruction = document.root.children.find(&:processing_instruction?)

      expect(instruction).not_to be_nil
      expect(instruction.name).to eq("pi")
      expect(instruction.text).to eq("data")
      expect(instruction.node_type).to eq(:processing_instruction)
    end

    it "preserves processing instructions and CDATA when serializing parsed XML" do
      output = document.to_xml

      expect(output).to include("<?pi data?>")
      expect(output).to include("<![CDATA[cdata text]]>")
    end

    it "uses the same order representation through to_h item_order" do
      parsed_hash = nil

      expect { parsed_hash = document.to_h }.not_to raise_error
      expect(order_data(parsed_hash.item_order)).to eq(expected_order)
    end
  end

  shared_examples "consistent shared adapter features" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    it "uses shared parse metadata preservation" do
      xml = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE root SYSTEM "root.dtd">
        <root><child/></root>
      XML

      document = adapter_class.parse(xml)

      expect(document.xml_declaration[:had_declaration]).to be true
      expect(document.doctype).to include(name: "root",
                                          public_id: nil,
                                          system_id: "root.dtd")
      expect(document.to_xml(declaration: true)).to include(
        '<!DOCTYPE root SYSTEM "root.dtd">',
      )
    end

    it "parses binary UTF-8 XML input through shared normalization" do
      document = adapter_class.parse("<root><name>μ</name></root>".b)

      expect(document.root.name).to eq("root")
      expect(document.root.element_children.first.text).to eq("μ")
    end

    it "transcodes non-UTF-8 strings from their declared encoding" do
      xml = "<root><name>\xC2\xA3</name></root>".b
      xml.force_encoding("ISO-8859-1")
      document = adapter_class.parse(xml)

      expect(document.root.element_children.first.text).to eq("Â£")
    end

    it "applies OOXML boolean post-processing through the shared finalizer" do
      xml = XmlAdapterSharedFeaturesSpec::BooleanElement
        .new(val: "true")
        .to_xml(prefix: true, fix_boolean_elements: true)

      expect(xml).to start_with("<w:b ")
      expect(xml).to include("xmlns:w=")
      expect(xml).not_to include("w:val=")
      expect(xml).to end_with("/>")
    end

    it "applies OOXML xml namespace attribute cleanup through the shared finalizer" do
      document = adapter_class.new(nil)

      expect(
        document.fix_ooxml_format('<w:t w:xml:space="preserve">x</w:t>'),
      ).to eq('<w:t xml:space="preserve">x</w:t>')
    end

    it "preserves processing instructions without matching them as elements" do
      xml = "<root><?foo ignored?><foo>bar</foo></root>"
      document = adapter_class.parse(xml)

      expect(document.root.children.any?(&:processing_instruction?)).to be true
      expect(document.root.element_children.map(&:text)).to eq(["bar"])
      expect(document.root.find_children_by_name("foo").map(&:text)).to eq(["bar"])
      expect(
        XmlAdapterSharedFeaturesSpec::ProcessingInstructionLookupElement
          .from_xml(xml)
          .foo,
      ).to eq("bar")
    end
  end

  describe Lutaml::Xml::Adapter::NokogiriAdapter do
    it_behaves_like "consistent order metadata", described_class
    it_behaves_like "consistent shared adapter features", described_class
  end

  describe Lutaml::Xml::Adapter::OxAdapter do
    it_behaves_like "consistent order metadata", described_class
    it_behaves_like "consistent shared adapter features", described_class
  end

  describe Lutaml::Xml::Adapter::OgaAdapter do
    it_behaves_like "consistent order metadata", described_class
    it_behaves_like "consistent shared adapter features", described_class
  end

  describe Lutaml::Xml::Adapter::RexmlAdapter do
    it_behaves_like "consistent order metadata", described_class
    it_behaves_like "consistent shared adapter features", described_class
  end
end
