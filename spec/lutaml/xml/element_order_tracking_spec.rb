# frozen_string_literal: true

require "spec_helper"

RSpec.describe "element_order_tracking (#909)" do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :first, :string
      attribute :second, :string

      xml do
        element "root"
        map_element "first", to: :first
        map_element "second", to: :second
      end
    end
  end

  let(:xml) { "<root><first>a</first><second>b</second></root>" }

  after { Lutaml::Model::Config.instance.element_order_tracking = true }

  it "tracks order by default" do
    instance = model_class.from_xml(xml)
    expect(instance.element_order).not_to be_nil
    expect(instance.first).to eq("a")
  end

  it "skips the summaries when disabled, values still deserialize" do
    Lutaml::Model::Config.instance.element_order_tracking = false
    instance = model_class.from_xml(xml)

    expect(instance.element_order).to be_nil
    expect(instance.first).to eq("a")
    expect(instance.second).to eq("b")
  end
end
