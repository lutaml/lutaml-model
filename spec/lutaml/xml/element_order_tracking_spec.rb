# frozen_string_literal: true

require "spec_helper"

RSpec.describe "element_order tracking configuration" do
  let(:classes) do
    item_class = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      xml do
        element "item"
        ordered
        map_element "name", to: :name
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
  let(:xml) do
    "<root><item><name>a</name></item><item><name>b</name></item></root>"
  end

  around do |example|
    old = Lutaml::Model::Config.instance.element_order_tracking
    example.run
  ensure
    Lutaml::Model::Config.instance.element_order_tracking = old
  end

  it "populates element_order by default" do
    Lutaml::Model::Config.instance.element_order_tracking = true
    root = root_class.from_xml(xml)
    item = root.item.first
    expect(item.element_order).not_to be_nil
    expect(item.element_order).not_to be_empty
    expect(root.to_xml).to include("<name>a</name>")
  end

  it "skips element_order summaries when tracking is off" do
    Lutaml::Model::Config.instance.element_order_tracking = false
    root = root_class.from_xml(xml)
    item = root.item.first
    expect(item.element_order).to be_nil
  end

  it "still deserializes values with tracking off" do
    Lutaml::Model::Config.instance.element_order_tracking = false
    root = root_class.from_xml(xml)
    expect(root.item.map(&:name)).to eq(%w[a b])
  end
end
