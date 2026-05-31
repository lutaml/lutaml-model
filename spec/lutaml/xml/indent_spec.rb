# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Indent configuration" do
  before do
    item_class = Class.new do
      include Lutaml::Model::Serialize

      attribute :name, :string

      xml do
        element "item"
        map_element "name", to: :name
      end
    end

    stub_const("IndentItem", item_class)

    test_class = Class.new do
      include Lutaml::Model::Serialize

      attribute :title, :string
      attribute :items, IndentItem, collection: true

      xml do
        element "container"
        map_element "title", to: :title
        map_element "item", to: :items
      end
    end

    stub_const("IndentContainer", test_class)
  end

  let(:model) do
    IndentContainer.new(
      title: "Test",
      items: [IndentItem.new(name: "a"), IndentItem.new(name: "b")],
    )
  end

  it "uses default indent of 2 spaces" do
    xml = model.to_xml
    expect(xml).to include("  <title>Test</title>")
    expect(xml).to include("  <item>")
  end

  it "produces compact output with indent: 0" do
    xml = model.to_xml(indent: 0)
    expect(xml).not_to include("\n  ")
    expect(xml).not_to include("\n    ")
  end

  it "uses 4-space indent when indent: 4" do
    xml = model.to_xml(indent: 4)
    expect(xml).to include("    <title>Test</title>")
    expect(xml).to include("    <item>")
  end

  it "nests consistently at multiple levels with indent: 4" do
    nested_class = Class.new do
      include Lutaml::Model::Serialize

      attribute :label, :string
      attribute :child, IndentItem

      xml do
        element "nested"
        map_element "label", to: :label
        map_element "item", to: :child
      end
    end

    stub_const("IndentNested", nested_class)

    container = Class.new do
      include Lutaml::Model::Serialize

      attribute :nested, IndentNested

      xml do
        element "root"
        map_element "nested", to: :nested
      end
    end

    stub_const("IndentRoot", container)

    instance = IndentRoot.new(
      nested: IndentNested.new(
        label: "outer",
        child: IndentItem.new(name: "inner"),
      ),
    )

    xml = instance.to_xml(indent: 4)
    expect(xml).to include("    <nested>")
    expect(xml).to include("        <label>outer</label>")
    expect(xml).to include("        <item>")
    expect(xml).to include("            <name>inner</name>")
  end

  it "preserves text content without extra whitespace" do
    xml = model.to_xml
    expect(xml).to include("<title>Test</title>")
    expect(xml).to include("<name>a</name>")
  end
end
