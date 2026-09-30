# frozen_string_literal: true

require "spec_helper"

class AnyElementNode < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :children, "AnyElementNode", collection: true

  xml do
    element "root"
    map_element "id", to: :id
    map_any_element to: :children
  end
end

RSpec.describe AnyElementNode do
  it "routes unmapped child elements to the catch-all collection" do
    doc = described_class.from_xml(<<~XML)
      <root>
        <id>r-1</id>
        <semantic__p>hello</semantic__p>
        <semantic__title>Nested</semantic__title>
        <semantic__p><semantic__em>deep</semantic__em></semantic__p>
      </root>
    XML

    expect(doc.id).to eq("r-1")
    expect(doc.children.size).to eq(3)
  end

  it "keeps explicit rules ahead of the catch-all" do
    doc = described_class.from_xml("<root><id>x</id></root>")
    expect(doc.id).to eq("x")
    expect(doc.children).to be_empty
  end

  it "nests catch-all children recursively" do
    doc = described_class.from_xml("<root><semantic__p><semantic__em>deep</semantic__em></semantic__p></root>")
    expect(doc.children.first.children.size).to eq(1)
  end
end
