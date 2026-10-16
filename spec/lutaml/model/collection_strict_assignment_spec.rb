# frozen_string_literal: true

require "spec_helper"

RSpec.describe "strict collection assignment" do
  let(:node_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
    end
  end

  let(:holder_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :items, "Node", collection: true
    end
  end

  before do
    stub_const("Node", node_class)
    stub_const("Holder", holder_class)
  end

  it "raises at the constructor boundary" do
    expect do
      Holder.new(items: [[Node.new(id: "a")], Node.new(id: "b")])
    end.to raise_error(Lutaml::Model::TypeError, /item 0 is an Array/)
  end

  it "raises at the writer boundary" do
    holder = Holder.new
    expect do
      holder.items = [Node.new, [Node.new]]
    end.to raise_error(Lutaml::Model::TypeError, /item 1 is an Array/)
  end

  it "raises for a custom collection class" do
    custom = Class.new(Lutaml::Model::Collection) do
      instances :node, "Node"
    end
    stub_const("NodeBag", custom)
    wrapper = Class.new(Lutaml::Model::Serializable) do
      attribute :bag, "NodeBag"
    end
    stub_const("BagHolder", wrapper)

    expect do
      BagHolder.new(bag: [[Node.new]])
    end.to raise_error(Lutaml::Model::TypeError, /nested arrays are not flattened/)
  end

  it "keeps flat assignment untouched" do
    holder = Holder.new(items: [Node.new(id: "x")])
    expect(holder.items.map(&:id)).to eq(["x"])
  end
end
