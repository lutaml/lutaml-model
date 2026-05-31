# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Full serialization pipeline" do
  before do
    item_class = Class.new do
      include Lutaml::Model::Serialize

      attribute :name, :string
      attribute :value, :string

      xml do
        element "item"
        map_element "name", to: :name
        map_element "value", to: :value
      end
    end

    stub_const("PipeItem", item_class)

    doc_class = Class.new do
      include Lutaml::Model::Serialize

      attribute :title, :string
      attribute :items, PipeItem, collection: true

      xml do
        element "document"
        map_element "title", to: :title
        map_element "item", to: :items
      end
    end

    stub_const("PipeDoc", doc_class)
  end

  let(:model) do
    PipeDoc.new(
      title: "Test",
      items: [
        PipeItem.new(name: "a", value: "1"),
        PipeItem.new(name: "b", value: "2"),
      ],
    )
  end

  it "produces identical output for identical models across multiple runs" do
    first = model.to_xml
    second = model.to_xml
    expect(first).to eq(second)
  end

  it "handles declaration + doctype + content together" do
    xml = model.to_xml(
      declaration: true,
      doctype: { name: "document", system_id: "doc.dtd" },
    )

    expect(xml).to start_with("<?xml")
    expect(xml).to include("<!DOCTYPE document SYSTEM \"doc.dtd\">")
    expect(xml).to include("<title>Test</title>")
    expect(xml).to include("<name>a</name>")
  end

  it "CRLF + indent=4 + declaration produces correct output" do
    xml = model.to_xml(
      line_ending: "\r\n",
      indent: 4,
      declaration: true,
    )

    expect(xml.lines).to all(end_with("\r\n"))
    expect(xml).to include("    <title>Test</title>")
    expect(xml).to include("<?xml")
  end

  it "round-trips complex XML with all features preserved" do
    input = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <document>
        <title>Original</title>
        <item>
          <name>x</name>
          <value>42</value>
        </item>
      </document>
    XML

    parsed = PipeDoc.from_xml(input)
    expect(parsed.title).to eq("Original")
    expect(parsed.items.length).to eq(1)
    expect(parsed.items.first.name).to eq("x")
    expect(parsed.items.first.value).to eq("42")

    output = parsed.to_xml(declaration: true)
    expect(output).to start_with("<?xml")
    expect(output).to include("<title>Original</title>")
    expect(output).to include("<name>x</name>")
  end

  it "round-trip preserves namespace declarations" do
    ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://example.com/ns"
      prefix_default "ex"
    end

    stub_const("PipeNs", ns)

    ns_child = Class.new do
      include Lutaml::Model::Serialize

      attribute :content, :string

      xml do
        element "child"
        namespace PipeNs
        map_element "content", to: :content
      end
    end

    stub_const("PipeNsChild", ns_child)

    ns_parent = Class.new do
      include Lutaml::Model::Serialize

      attribute :child, PipeNsChild

      xml do
        element "parent"
        map_element "child", to: :child
      end
    end

    stub_const("PipeNsParent", ns_parent)

    instance = PipeNsParent.new(child: PipeNsChild.new(content: "data"))
    xml = instance.to_xml

    expect(xml).to include("xmlns")

    parsed = PipeNsParent.from_xml(xml)
    expect(parsed.child.content).to eq("data")
  end
end
