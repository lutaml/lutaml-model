# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML plan fast path" do
  let(:classes) do
    item_class = Class.new(Lutaml::Model::Serializable) do
      attribute :id, :integer
      attribute :name, :string
      attribute :tags, :string, collection: true

      xml do
        element "item"
        map_attribute "id", to: :id
        map_element "name", to: :name
        map_element "tag", to: :tags
      end
    end
    root_class = Class.new(Lutaml::Model::Serializable) do
      attribute :item, item_class, collection: true

      xml do
        element "root"
        map_element "item", to: :item
      end
    end
    [item_class, root_class]
  end

  let(:item_class) { classes[0] }
  let(:root_class) { classes[1] }

  around do |example|
    old = Lutaml::Model::Config.instance.xml_plan_fast_path
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
    example.run
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = old
  end

  it "is opt-in and off by default" do
    expect(Lutaml::Model::Configuration.new.xml_plan_fast_path).to be(false)
  end

  it "hydrates equal to the interpretive path" do
    xml = root_class.new(item: [
                           item_class.new(id: 1, name: "a", tags: %w[x y]),
                           item_class.new(id: 2, name: "b", tags: %w[z]),
                         ]).to_xml

    expect(root_class.from_xml(xml).item).to eq(root_class.new(item: [
                                                                 item_class.new(id: 1, name: "a", tags: %w[x y]),
                                                                 item_class.new(id: 2, name: "b", tags: %w[z]),
                                                               ]).item)
  end

  it "matches the interpretive path on missing elements" do
    xml = <<~XML
      <root>
        <item id="1"><name>A</name><tag>x</tag></item>
        <item id="2"><tag>y</tag><tag>z</tag></item>
        <item id="3"><name>C</name></item>
      </root>
    XML

    parsed = root_class.from_xml(xml)
    expect(parsed.item.map { |i| [i.id, i.name, i.tags] })
      .to eq([[1, "A", %w[x]], [2, nil, %w[y z]], [3, "C", []]])
  end

  it "wraps engine parse errors as InvalidFormatError" do
    Lutaml::Model::Config.with_adapter(xml: :leptris) do
      expect { root_class.from_xml("<root><item>") }
        .to raise_error(Lutaml::Model::InvalidFormatError)
    end
  end

  it "falls back for non-compilable models" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :note, :string

      xml do
        element "doc"
        map_element "note", to: :note, with: { from: :note_from }
      end

      def note_from(instance, value)
        instance.note = value.text
      end
    end

    expect(Lutaml::Xml::PlanCompiler.compile(klass,
                                             Lutaml::Model::Config.default_register)).to be_nil
    expect(klass.from_xml("<doc><note>hi</note></doc>").note).to eq("hi")
  end
end
