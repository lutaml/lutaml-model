# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model do
  let(:model) do
    Class.new(Lutaml::Model::Serializable) do
      attr_accessor :name
      def name
        "AnyElementModel"
      end

      attribute :id, :string
      attribute :children, "AnyElementModel", collection: true
      attribute :tag, :string

      xml do
        element "root"
        map_element "id", to: :id
        map_any_element to: :children
      end
    end
  end

  it "routes unmapped child elements to the catch-all collection" do
    doc = model.from_xml(<<~XML)
      <root>
        <id>r-1</id>
        <semantic__p>hello</semantic__p>
        <semantic__title>Nested</semantic__title>
        <semantic__p><semantic__em>deep</semantic__em></semantic__p>
      </root>
    XML

    expect(doc.id).to eq("r-1")
    expect(doc.children.size).to eq(3)
    names = doc.children.map { |c| Array(c.element_order).filter_map { |e| e.name unless e.text? } }
    expect(names).to eq([["semantic__em"], [], []])
  end

  it "keeps explicit rules ahead of the catch-all" do
    doc = model.from_xml("<root><id>x</id></root>")
    expect(doc.id).to eq("x")
    expect(doc.children).to be_empty
  end

  it "parses text content of catch-all children" do
    doc = model.from_xml("<root><semantic__p>words</semantic__p></root>")
    expect(doc.children.size).to eq(1)
  end
end
